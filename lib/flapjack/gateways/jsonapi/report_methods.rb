#!/usr/bin/env ruby

require 'sinatra/base'

require 'flapjack/data/entity'
require 'flapjack/data/entity_check'

require 'flapjack/gateways/jsonapi/entity_check_presenter'

module Flapjack

  module Gateways

    class JSONAPI < Sinatra::Base

      module ReportMethods

        module Helpers

          def load_api_data(entity_ids, entity_check_names, result_type, &block)
            entities_by_name             = {}
            entity_checks_by_entity_name = {}

            unless entity_ids.nil? || entity_ids.empty?
              entity_ids.each do |entity_id|
                entity = find_entity_by_id(entity_id)
                entities_by_name[entity.name] = entity
                check_list_names = entity.check_list
                entity_checks_by_entity_name[entity.name] = check_list_names.collect {|entity_check_name|
                  find_entity_check_by_name(entity.name, entity_check_name)
                }
              end
            end

            unless entity_check_names.nil? || entity_check_names.empty?
              entity_check_names.each do |entity_check_name|
                entity_name, check_name = entity_check_name.split(':', 2)
                entities_by_name[entity_name] ||= find_entity(entity_name)

                entity_checks_by_entity_name[entity_name] ||= []
                entity_checks_by_entity_name[entity_name] << find_entity_check_by_name(entity_name, check_name)
              end
            end

            entity_data = entities_by_name.inject([]) do |memo, (entity_name, entity)|
              memo << {
                'id'    => entity.id,
                'name'  => entity_name,
                'links' => {
                  'checks' => entity_checks_by_entity_name[entity_name].collect {|entity_check|
                    "#{entity_name}:#{entity_check.name}"
                  },
                }
              }
              memo
            end

            entity_check_data = entity_checks_by_entity_name.inject([]) do |memo, (entity_name, entity_checks)|
              memo += entity_checks.collect do |entity_check|
                entity_check_name = entity_check.name
                {
                  'id'        => "#{entity_name}:#{entity_check_name}",
                  'name'      => entity_check_name,
                  result_type => yield(Flapjack::Gateways::JSONAPI::EntityCheckPresenter.new(entity_check))
                }
              end
              memo
            end

            [entity_data, entity_check_data]
          end

        end

        def self.registered(app)
          app.helpers Flapjack::Gateways::JSONAPI::Helpers
          app.helpers Flapjack::Gateways::JSONAPI::ReportMethods::Helpers

          app.get %r{/(entities|checks)/([^/]+)/(status|outage|(?:un)?scheduled_maintenance|downtime)_report} do
            entities_or_checks = params[:captures][0]
            action = params[:captures][2]

            args = []

            unless 'status'.eql?(action)
              args += [validate_and_parsetime(params[:start_time]),
                       validate_and_parsetime(params[:end_time])]
            end

            report_type = case action
            when 'status'
              'statuses'
            when 'outage'
              'outages'
            when 'scheduled_maintenance'
              'scheduled_maintenances'
            when 'unscheduled_maintenance'
              'unscheduled_maintenances'
            when 'downtime'
              'downtimes'
            end

            entity_data, check_data = case entities_or_checks
            when 'entities'
              entity_ids = params[:captures][1].split(',')
              load_api_data(entity_ids, nil, report_type) {|presenter|
                presenter.send(action, *args)
              }
            when 'checks'
              entity_check_names = params[:captures][1].split(',')
              load_api_data(nil, entity_check_names, report_type) {|presenter|
                presenter.send(action, *args)
              }
            end

            "{\"#{action}_reports\":" + entity_data.to_json +
              ",\"linked\":{\"checks\":" + check_data.to_json + "}}"
          end

        end

      end

    end

  end

end
