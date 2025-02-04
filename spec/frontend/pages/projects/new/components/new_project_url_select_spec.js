import {
  GlButton,
  GlDropdown,
  GlDropdownItem,
  GlDropdownSectionHeader,
  GlSearchBoxByType,
} from '@gitlab/ui';
import { createLocalVue, mount, shallowMount } from '@vue/test-utils';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { mockTracking, unmockTracking } from 'helpers/tracking_helper';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import eventHub from '~/pages/projects/new/event_hub';
import NewProjectUrlSelect from '~/pages/projects/new/components/new_project_url_select.vue';
import searchQuery from '~/pages/projects/new/queries/search_namespaces_where_user_can_create_projects.query.graphql';

describe('NewProjectUrlSelect component', () => {
  let wrapper;

  const data = {
    currentUser: {
      groups: {
        nodes: [
          {
            id: 'gid://gitlab/Group/26',
            fullPath: 'flightjs',
          },
          {
            id: 'gid://gitlab/Group/28',
            fullPath: 'h5bp',
          },
          {
            id: 'gid://gitlab/Group/30',
            fullPath: 'h5bp/subgroup',
          },
        ],
      },
      namespace: {
        id: 'gid://gitlab/Namespace/1',
        fullPath: 'root',
      },
    },
  };

  const localVue = createLocalVue();
  localVue.use(VueApollo);

  const defaultProvide = {
    namespaceFullPath: 'h5bp',
    namespaceId: '28',
    rootUrl: 'https://gitlab.com/',
    trackLabel: 'blank_project',
    userNamespaceFullPath: 'root',
    userNamespaceId: '1',
  };

  const mountComponent = ({
    search = '',
    queryResponse = data,
    provide = defaultProvide,
    mountFn = shallowMount,
  } = {}) => {
    const requestHandlers = [[searchQuery, jest.fn().mockResolvedValue({ data: queryResponse })]];
    const apolloProvider = createMockApollo(requestHandlers);

    return mountFn(NewProjectUrlSelect, {
      localVue,
      apolloProvider,
      provide,
      data() {
        return {
          search,
        };
      },
    });
  };

  const findButtonLabel = () => wrapper.findComponent(GlButton);
  const findDropdown = () => wrapper.findComponent(GlDropdown);
  const findInput = () => wrapper.findComponent(GlSearchBoxByType);
  const findHiddenInput = () => wrapper.find('input');

  afterEach(() => {
    wrapper.destroy();
  });

  it('renders the root url as a label', () => {
    wrapper = mountComponent();

    expect(findButtonLabel().text()).toBe(defaultProvide.rootUrl);
    expect(findButtonLabel().props('label')).toBe(true);
  });

  describe('when namespaceId is provided', () => {
    beforeEach(() => {
      wrapper = mountComponent();
    });

    it('renders a dropdown with the given namespace full path as the text', () => {
      expect(findDropdown().props('text')).toBe(defaultProvide.namespaceFullPath);
    });

    it('renders a dropdown with the given namespace id in the hidden input', () => {
      expect(findHiddenInput().attributes('value')).toBe(defaultProvide.namespaceId);
    });
  });

  describe('when namespaceId is not provided', () => {
    const provide = {
      ...defaultProvide,
      namespaceFullPath: undefined,
      namespaceId: undefined,
    };

    beforeEach(() => {
      wrapper = mountComponent({ provide });
    });

    it("renders a dropdown with the user's namespace full path as the text", () => {
      expect(findDropdown().props('text')).toBe(defaultProvide.userNamespaceFullPath);
    });

    it("renders a dropdown with the user's namespace id in the hidden input", () => {
      expect(findHiddenInput().attributes('value')).toBe(defaultProvide.userNamespaceId);
    });
  });

  it('focuses on the input when the dropdown is opened', async () => {
    wrapper = mountComponent({ mountFn: mount });

    jest.runOnlyPendingTimers();
    await wrapper.vm.$nextTick();

    const spy = jest.spyOn(findInput().vm, 'focusInput');

    findDropdown().vm.$emit('shown');

    expect(spy).toHaveBeenCalledTimes(1);
  });

  it('renders expected dropdown items', async () => {
    wrapper = mountComponent({ mountFn: mount });

    jest.runOnlyPendingTimers();
    await wrapper.vm.$nextTick();

    const listItems = wrapper.findAll('li');

    expect(listItems).toHaveLength(6);
    expect(listItems.at(0).findComponent(GlDropdownSectionHeader).text()).toBe('Groups');
    expect(listItems.at(1).text()).toBe(data.currentUser.groups.nodes[0].fullPath);
    expect(listItems.at(2).text()).toBe(data.currentUser.groups.nodes[1].fullPath);
    expect(listItems.at(3).text()).toBe(data.currentUser.groups.nodes[2].fullPath);
    expect(listItems.at(4).findComponent(GlDropdownSectionHeader).text()).toBe('Users');
    expect(listItems.at(5).text()).toBe(data.currentUser.namespace.fullPath);
  });

  describe('when selecting from a group template', () => {
    const groupId = getIdFromGraphQLId(data.currentUser.groups.nodes[1].id);

    beforeEach(async () => {
      wrapper = mountComponent({ mountFn: mount });

      jest.runOnlyPendingTimers();
      await wrapper.vm.$nextTick();

      eventHub.$emit('select-template', groupId);
    });

    it('filters the dropdown items to the selected group and children', async () => {
      const listItems = wrapper.findAll('li');

      expect(listItems).toHaveLength(3);
      expect(listItems.at(0).findComponent(GlDropdownSectionHeader).text()).toBe('Groups');
      expect(listItems.at(1).text()).toBe(data.currentUser.groups.nodes[1].fullPath);
      expect(listItems.at(2).text()).toBe(data.currentUser.groups.nodes[2].fullPath);
    });

    it('sets the selection to the group', async () => {
      expect(findDropdown().props('text')).toBe(data.currentUser.groups.nodes[1].fullPath);
    });
  });

  it('renders `No matches found` when there are no matching dropdown items', async () => {
    const queryResponse = {
      currentUser: {
        groups: {
          nodes: [],
        },
        namespace: {
          id: 'gid://gitlab/Namespace/1',
          fullPath: 'root',
        },
      },
    };

    wrapper = mountComponent({ search: 'no matches', queryResponse, mountFn: mount });

    jest.runOnlyPendingTimers();
    await wrapper.vm.$nextTick();

    expect(wrapper.find('li').text()).toBe('No matches found');
  });

  it('updates hidden input with selected namespace', async () => {
    wrapper = mountComponent();

    jest.runOnlyPendingTimers();
    await wrapper.vm.$nextTick();

    wrapper.findComponent(GlDropdownItem).vm.$emit('click');

    await wrapper.vm.$nextTick();

    expect(findHiddenInput().attributes()).toMatchObject({
      name: 'project[namespace_id]',
      value: getIdFromGraphQLId(data.currentUser.groups.nodes[0].id).toString(),
    });
  });

  it('tracks clicking on the dropdown', () => {
    wrapper = mountComponent();

    const trackingSpy = mockTracking(undefined, wrapper.element, jest.spyOn);

    findDropdown().vm.$emit('show');

    expect(trackingSpy).toHaveBeenCalledWith(undefined, 'activate_form_input', {
      label: defaultProvide.trackLabel,
      property: 'project_path',
    });

    unmockTracking();
  });
});
