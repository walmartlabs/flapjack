require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::UnscheduledMaintenanceLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:unscheduled_maintenance) { double(Flapjack::Data::UnscheduledMaintenance,
                                  :id => unscheduled_maintenance_data[:id]) }
  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }

  let(:sm_check_by_start) { double('sm_check_by_start') }
  let(:sm_check_by_end)   { double('sm_check_by_end') }

  it 'shows the check for a unscheduled maintenance period' do
    expect(unscheduled_maintenance).to receive(:check).and_return(check)

    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:find_by_id!).with(unscheduled_maintenance.id).
      and_return(unscheduled_maintenance)

    get "/unscheduled_maintenances/#{unscheduled_maintenance.id}/check"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => {:type => 'check', :id => check.id},
      :links => {
        :self    => "http://example.org/unscheduled_maintenances/#{unscheduled_maintenance.id}/links/check",
        :related => "http://example.org/unscheduled_maintenances/#{unscheduled_maintenance.id}/check",
      }
    ))
  end

  it 'changes the check for a unscheduled maintenance period' do
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:lock).with(Flapjack::Data::Check).and_yield

    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:find_by_id!).with(unscheduled_maintenance.id).
      and_return(unscheduled_maintenance)
    expect(Flapjack::Data::Check).to receive(:find_by_id!).with(check.id).
      and_return(check)

    expect(unscheduled_maintenance).to receive(:check=).with(check)

    patch "/unscheduled_maintenances/#{unscheduled_maintenance.id}/links/check",
      Flapjack.dump_json(:data => {
        :type => 'check', :id => check.id
      }), jsonapi_env
    expect(last_response.status).to eq(204)
  end

  it 'clears the check for a unscheduled maintenance period' do
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:lock).with(Flapjack::Data::Check).and_yield

    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:find_by_id!).with(unscheduled_maintenance.id).
      and_return(unscheduled_maintenance)

    expect(unscheduled_maintenance).to receive(:check=).with(nil)

    patch "/unscheduled_maintenances/#{unscheduled_maintenance.id}/links/check",
      Flapjack.dump_json(:data => {
        :type => 'check', :id => nil
      }), jsonapi_env
    expect(last_response.status).to eq(204)
  end

end
