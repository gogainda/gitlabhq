/* eslint-disable */
import { EXTENSION_ICONS } from '../constants';
import issuesCollapsedQuery from './issues_collapsed.query.graphql';
import issuesQuery from './issues.query.graphql';

export default {
  // Give the extension a name
  // Make it easier to track in Vue dev tools
  name: 'WidgetIssues',
  i18n: {
    label: 'Issues',
    loading: 'Loading issues...',
  },
  // Add an array of props
  // These then get mapped to values stored in the MR Widget store
  props: ['targetProjectFullPath', 'conflictsDocsPath'],
  // Add any extra computed props in here
  computed: {
    // Small summary text to be displayed in the collapsed state
    // Receives the collapsed data as an argument
    summary(count) {
      return 'Summary text<br/>Second line';
    },
    // Status icon to be used next to the summary text
    // Receives the collapsed data as an argument
    statusIcon(count) {
      return EXTENSION_ICONS.warning;
    },
    // Tertiary action buttons that will take the user elsewhere
    // in the GitLab app
    tertiaryButtons() {
      return [{ text: 'Full report', href: this.conflictsDocsPath, target: '_blank' }];
    },
  },
  methods: {
    // Fetches the collapsed data
    // Ideally, this request should return the smallest amount of data possible
    // Receives an object of all the props passed in to the extension
    fetchCollapsedData({ targetProjectFullPath }) {
      return this.$apollo
        .query({ query: issuesCollapsedQuery, variables: { projectPath: targetProjectFullPath } })
        .then(({ data }) => data.project.issues.count);
    },
    // Fetches the full data when the extension is expanded
    // Receives an object of all the props passed in to the extension
    fetchFullData({ targetProjectFullPath }) {
      return this.$apollo
        .query({ query: issuesQuery, variables: { projectPath: targetProjectFullPath } })
        .then(({ data }) => {
          // Return some transformed data to be rendered in the expanded state
          return data.project.issues.nodes.map((issue) => ({
            id: issue.id, // Required: The ID of the object
            text: issue.title, // Required: The text to get used on each row
            // Icon to get rendered on the side of each row
            icon: {
              // Required: Name maps to an icon in GitLabs SVG
              name: issue.state === 'closed' ? EXTENSION_ICONS.error : EXTENSION_ICONS.success,
            },
            // Badges get rendered next to the text on each row
            // badge: issue.state === 'closed' && {
            //   text: 'Closed', // Required: Text to be used inside of the badge
            //   // variant: 'info', // Optional: The variant of the badge, maps to GitLab UI variants
            // },
            // Each row can have its own link that will take the user elsewhere
            // link: {
            //   href: 'https://google.com', // Required: href for the link
            //   text: 'Link text', // Required: Text to be used inside the link
            // },
          }));
        });
    },
  },
};
