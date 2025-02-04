# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::CustomerRelations::Contacts::Update do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }

  let(:first_name) { 'Lionel' }
  let(:last_name) { 'Smith' }
  let(:email) { 'ls@gitlab.com' }
  let(:description) { 'VIP' }
  let(:does_not_exist_or_no_permission) { "The resource that you are attempting to access does not exist or you don't have permission to perform this action" }
  let(:contact) { create(:contact, group: group) }
  let(:attributes) do
    {
      id: contact.to_global_id,
      first_name: first_name,
      last_name: last_name,
      email: email,
      description: description
    }
  end

  describe '#resolve' do
    subject(:resolve_mutation) do
      described_class.new(object: nil, context: { current_user: user }, field: nil).resolve(
        attributes
      )
    end

    context 'when the user does not have permission to update a contact' do
      before do
        group.add_reporter(user)
      end

      it 'raises an error' do
        expect { resolve_mutation }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
          .with_message(does_not_exist_or_no_permission)
      end
    end

    context 'when the contact does not exist' do
      it 'raises an error' do
        attributes[:id] = "gid://gitlab/CustomerRelations::Contact/#{non_existing_record_id}"

        expect { resolve_mutation }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
          .with_message(does_not_exist_or_no_permission)
      end
    end

    context 'when the user has permission to update a contact' do
      before_all do
        group.add_developer(user)
      end

      it 'updates the organization with correct values' do
        expect(resolve_mutation[:contact]).to have_attributes(attributes)
      end

      context 'when the feature is disabled' do
        before do
          stub_feature_flags(customer_relations: false)
        end

        it 'raises an error' do
          expect { resolve_mutation }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
            .with_message('Feature disabled')
        end
      end
    end
  end

  specify { expect(described_class).to require_graphql_authorizations(:admin_contact) }
end
