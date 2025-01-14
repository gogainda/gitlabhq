# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::DependencyProxyForContainersController do
  include HttpBasicAuthHelpers
  include DependencyProxyHelpers
  include WorkhorseHelpers

  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:group) { create(:group, :private) }

  let(:token_response) { { status: :success, token: 'abcd1234' } }
  let(:jwt) { build_jwt(user) }
  let(:token_header) { "Bearer #{jwt.encoded}" }
  let(:snowplow_gitlab_standard_context) { { namespace: group, user: user } }

  shared_examples 'without a token' do
    before do
      request.headers['HTTP_AUTHORIZATION'] = nil
    end

    context 'feature flag disabled' do
      let_it_be(:group) { create(:group) }

      before do
        stub_feature_flags(dependency_proxy_for_private_groups: false)
      end

      it { is_expected.to have_gitlab_http_status(:ok) }
    end

    it { is_expected.to have_gitlab_http_status(:unauthorized) }
  end

  shared_examples 'feature flag disabled with private group' do
    before do
      stub_feature_flags(dependency_proxy_for_private_groups: false)
    end

    it 'returns not found' do
      group.update!(visibility_level: Gitlab::VisibilityLevel::PRIVATE)

      subject

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  shared_examples 'without permission' do
    context 'with invalid user' do
      before do
        user = double('bad_user', id: 999)
        token_header = "Bearer #{build_jwt(user).encoded}"
        request.headers['HTTP_AUTHORIZATION'] = token_header
      end

      it { is_expected.to have_gitlab_http_status(:unauthorized) }
    end

    context 'with valid user that does not have access' do
      before do
        request.headers['HTTP_AUTHORIZATION'] = token_header
      end

      it { is_expected.to have_gitlab_http_status(:not_found) }
    end

    context 'with deploy token from a different group,' do
      let_it_be(:user) { create(:deploy_token, :group, :dependency_proxy_scopes) }

      it { is_expected.to have_gitlab_http_status(:not_found) }
    end

    context 'with revoked deploy token' do
      let_it_be(:user) { create(:deploy_token, :revoked, :group, :dependency_proxy_scopes) }
      let_it_be(:group_deploy_token) { create(:group_deploy_token, deploy_token: user, group: group) }

      it { is_expected.to have_gitlab_http_status(:unauthorized) }
    end

    context 'with expired deploy token' do
      let_it_be(:user) { create(:deploy_token, :expired, :group, :dependency_proxy_scopes) }
      let_it_be(:group_deploy_token) { create(:group_deploy_token, deploy_token: user, group: group) }

      it { is_expected.to have_gitlab_http_status(:unauthorized) }
    end

    context 'with deploy token with insufficient scopes' do
      let_it_be(:user) { create(:deploy_token, :group) }
      let_it_be(:group_deploy_token) { create(:group_deploy_token, deploy_token: user, group: group) }

      it { is_expected.to have_gitlab_http_status(:not_found) }
    end

    context 'when a group is not found' do
      before do
        expect(Group).to receive(:find_by_full_path).and_return(nil)
      end

      it { is_expected.to have_gitlab_http_status(:not_found) }
    end

    context 'when user is not found' do
      before do
        allow(User).to receive(:find).and_return(nil)
      end

      it { is_expected.to have_gitlab_http_status(:unauthorized) }
    end
  end

  shared_examples 'not found when disabled' do
    context 'feature disabled' do
      before do
        disable_dependency_proxy
      end

      it 'returns 404' do
        subject

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  before do
    allow(Gitlab.config.dependency_proxy)
      .to receive(:enabled).and_return(true)

    allow_next_instance_of(DependencyProxy::RequestTokenService) do |instance|
      allow(instance).to receive(:execute).and_return(token_response)
    end

    request.headers['HTTP_AUTHORIZATION'] = token_header
  end

  describe 'GET #manifest' do
    let_it_be(:manifest) { create(:dependency_proxy_manifest) }

    let(:pull_response) { { status: :success, manifest: manifest, from_cache: false } }

    before do
      allow_next_instance_of(DependencyProxy::FindOrCreateManifestService) do |instance|
        allow(instance).to receive(:execute).and_return(pull_response)
      end
    end

    subject { get_manifest }

    context 'feature enabled' do
      before do
        enable_dependency_proxy
      end

      it_behaves_like 'without a token'
      it_behaves_like 'without permission'
      it_behaves_like 'feature flag disabled with private group'

      context 'remote token request fails' do
        let(:token_response) do
          {
            status: :error,
            http_status: 503,
            message: 'Service Unavailable'
          }
        end

        before do
          group.add_guest(user)
        end

        it 'proxies status from the remote token request', :aggregate_failures do
          subject

          expect(response).to have_gitlab_http_status(:service_unavailable)
          expect(response.body).to eq('Service Unavailable')
        end
      end

      context 'remote manifest request fails' do
        let(:pull_response) do
          {
            status: :error,
            http_status: 400,
            message: ''
          }
        end

        before do
          group.add_guest(user)
        end

        it 'proxies status from the remote manifest request', :aggregate_failures do
          subject

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(response.body).to be_empty
        end
      end

      context 'a valid user' do
        before do
          group.add_guest(user)
        end

        it_behaves_like 'a successful manifest pull'
        it_behaves_like 'a package tracking event', described_class.name, 'pull_manifest'

        context 'with a cache entry' do
          let(:pull_response) { { status: :success, manifest: manifest, from_cache: true } }

          it_behaves_like 'returning response status', :success
          it_behaves_like 'a package tracking event', described_class.name, 'pull_manifest_from_cache'
        end
      end

      context 'a valid deploy token' do
        let_it_be(:user) { create(:deploy_token, :dependency_proxy_scopes, :group) }
        let_it_be(:group_deploy_token) { create(:group_deploy_token, deploy_token: user, group: group) }

        it_behaves_like 'a successful manifest pull'

        context 'pulling from a subgroup' do
          let_it_be_with_reload(:parent_group) { create(:group) }
          let_it_be_with_reload(:group) { create(:group, parent: parent_group) }

          before do
            parent_group.create_dependency_proxy_setting!(enabled: true)
            group_deploy_token.update_column(:group_id, parent_group.id)
          end

          it_behaves_like 'a successful manifest pull'
        end
      end
    end

    it_behaves_like 'not found when disabled'

    def get_manifest
      get :manifest, params: { group_id: group.to_param, image: 'alpine', tag: '3.9.2' }
    end
  end

  describe 'GET #blob' do
    let(:blob) { create(:dependency_proxy_blob, group: group) }

    let(:blob_sha) { blob.file_name.sub('.gz', '') }

    subject { get_blob }

    context 'feature enabled' do
      before do
        enable_dependency_proxy
      end

      it_behaves_like 'without a token'
      it_behaves_like 'without permission'
      it_behaves_like 'feature flag disabled with private group'

      context 'a valid user' do
        before do
          group.add_guest(user)
        end

        it_behaves_like 'a successful blob pull'
        it_behaves_like 'a package tracking event', described_class.name, 'pull_blob_from_cache'

        context 'when cache entry does not exist' do
          let(:blob_sha) { 'a3ed95caeb02ffe68cdd9fd84406680ae93d633cb16422d00e8a7c22955b46d4' }

          it 'returns Workhorse send-dependency instructions' do
            subject

            send_data_type, send_data = workhorse_send_data
            header, url = send_data.values_at('Header', 'Url')

            expect(send_data_type).to eq('send-dependency')
            expect(header).to eq("Authorization" => ["Bearer abcd1234"])
            expect(url).to eq(DependencyProxy::Registry.blob_url('alpine', blob_sha))
            expect(response.headers['Content-Type']).to eq('application/gzip')
            expect(response.headers['Content-Disposition']).to eq(
              ActionDispatch::Http::ContentDisposition.format(disposition: 'attachment', filename: blob.file_name)
            )
          end
        end
      end

      context 'a valid deploy token' do
        let_it_be(:user) { create(:deploy_token, :group, :dependency_proxy_scopes) }
        let_it_be(:group_deploy_token) { create(:group_deploy_token, deploy_token: user, group: group) }

        it_behaves_like 'a successful blob pull'

        context 'pulling from a subgroup' do
          let_it_be_with_reload(:parent_group) { create(:group) }
          let_it_be_with_reload(:group) { create(:group, parent: parent_group) }

          before do
            parent_group.create_dependency_proxy_setting!(enabled: true)
            group_deploy_token.update_column(:group_id, parent_group.id)
          end

          it_behaves_like 'a successful blob pull'
        end
      end

      context 'when dependency_proxy_workhorse disabled' do
        let(:blob_response) { { status: :success, blob: blob, from_cache: false } }

        before do
          stub_feature_flags(dependency_proxy_workhorse: false)

          allow_next_instance_of(DependencyProxy::FindOrCreateBlobService) do |instance|
            allow(instance).to receive(:execute).and_return(blob_response)
          end
        end

        context 'remote blob request fails' do
          let(:blob_response) do
            {
              status: :error,
              http_status: 400,
              message: ''
            }
          end

          before do
            group.add_guest(user)
          end

          it 'proxies status from the remote blob request', :aggregate_failures do
            subject

            expect(response).to have_gitlab_http_status(:bad_request)
            expect(response.body).to be_empty
          end
        end

        context 'a valid user' do
          before do
            group.add_guest(user)
          end

          it_behaves_like 'a successful blob pull'
          it_behaves_like 'a package tracking event', described_class.name, 'pull_blob'

          context 'with a cache entry' do
            let(:blob_response) { { status: :success, blob: blob, from_cache: true } }

            it_behaves_like 'returning response status', :success
            it_behaves_like 'a package tracking event', described_class.name, 'pull_blob_from_cache'
          end
        end

        context 'a valid deploy token' do
          let_it_be(:user) { create(:deploy_token, :group, :dependency_proxy_scopes) }
          let_it_be(:group_deploy_token) { create(:group_deploy_token, deploy_token: user, group: group) }

          it_behaves_like 'a successful blob pull'

          context 'pulling from a subgroup' do
            let_it_be_with_reload(:parent_group) { create(:group) }
            let_it_be_with_reload(:group) { create(:group, parent: parent_group) }

            before do
              parent_group.create_dependency_proxy_setting!(enabled: true)
              group_deploy_token.update_column(:group_id, parent_group.id)
            end

            it_behaves_like 'a successful blob pull'
          end
        end
      end
    end

    it_behaves_like 'not found when disabled'

    def get_blob
      get :blob, params: { group_id: group.to_param, image: 'alpine', sha: blob_sha }
    end
  end

  describe 'GET #authorize_upload_blob' do
    let(:blob_sha) { 'a3ed95caeb02ffe68cdd9fd84406680ae93d633cb16422d00e8a7c22955b46d4' }

    subject(:authorize_upload_blob) do
      request.headers.merge!(workhorse_internal_api_request_header)

      get :authorize_upload_blob, params: { group_id: group.to_param, image: 'alpine', sha: blob_sha }
    end

    it_behaves_like 'without permission'

    context 'with a valid user' do
      before do
        group.add_guest(user)
      end

      it 'sends Workhorse file upload instructions', :aggregate_failures do
        authorize_upload_blob

        expect(response.headers['Content-Type']).to eq(Gitlab::Workhorse::INTERNAL_API_CONTENT_TYPE)
        expect(json_response['TempPath']).to eq(DependencyProxy::FileUploader.workhorse_local_upload_path)
      end
    end
  end

  describe 'GET #upload_blob' do
    let(:blob_sha) { 'a3ed95caeb02ffe68cdd9fd84406680ae93d633cb16422d00e8a7c22955b46d4' }
    let(:file) { fixture_file_upload("spec/fixtures/dependency_proxy/#{blob_sha}.gz", 'application/gzip') }

    subject do
      request.headers.merge!(workhorse_internal_api_request_header)

      get :upload_blob, params: {
        group_id: group.to_param,
        image: 'alpine',
        sha: blob_sha,
        file: file
      }
    end

    it_behaves_like 'without permission'

    context 'with a valid user' do
      before do
        group.add_guest(user)

        expect_next_found_instance_of(Group) do |instance|
          expect(instance).to receive_message_chain(:dependency_proxy_blobs, :create!)
        end
      end

      it_behaves_like 'a package tracking event', described_class.name, 'pull_blob'
    end
  end

  def enable_dependency_proxy
    group.create_dependency_proxy_setting!(enabled: true)
  end

  def disable_dependency_proxy
    group.create_dependency_proxy_setting!(enabled: false)
  end
end
