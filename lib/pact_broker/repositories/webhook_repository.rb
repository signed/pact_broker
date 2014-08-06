require 'sequel'
require 'pact_broker/models/webhook'
require 'pact_broker/db'

module PactBroker
  module Repositories

    class WebhookRepository

      # Experimenting with decoupling the model from the database representation.
      # Sure makes it messier for saving/retrieving.

      include Repositories

      def create webhook, consumer, provider
        db_webhook = Webhook.from_model webhook
        db_webhook.consumer_id = consumer.id
        db_webhook.provider_id = provider.id
        db_webhook.uuid = SecureRandom.urlsafe_base64
        db_webhook.save

        webhook.request.headers.each_pair do | name, value |
          WebhookHeader.from_model(name, value, db_webhook.id).save
        end

        find_by_uuid db_webhook.uuid
      end

      def find_by_uuid uuid
        db_webhook = Webhook.where(uuid: uuid).single_record
        return nil if db_webhook.nil?
        db_webhook.to_model
      end

    end

    class Webhook < Sequel::Model

      set_primary_key :id
      associate(:many_to_one, :provider, :class => "PactBroker::Models::Pacticipant", :key => :provider_id, :primary_key => :id)
      associate(:many_to_one, :consumer, :class => "PactBroker::Models::Pacticipant", :key => :consumer_id, :primary_key => :id)


      def self.from_model webhook
        is_json_request_body = !(String === webhook.request.body || webhook.request.body.nil?) # Can't rely on people to set content type
          new(
            uuid: webhook.uuid,
            method: webhook.request.method,
            url: webhook.request.url,
            body: (is_json_request_body ? webhook.request.body.to_json : webhook.request.body),
            is_json_request_body: is_json_request_body
          )
      end

      def to_model
        Models::Webhook.new(
          uuid: uuid,
          consumer: consumer,
          provider: provider,
          request: Models::WebhookRequest.new(request_attributes))
      end

      def request_attributes
        values.merge(headers: headers, body: parsed_body)
      end

      def headers
        WebhookHeader.where(webhook_id: id).all.each_with_object({}) do | header, hash |
          hash[header[:name]] = header[:value]
        end
      end

      def parsed_body
        if body && is_json_request_body
           JSON.parse(body)
        else
          body
        end
      end

    end

    class WebhookHeader < Sequel::Model

      associate(:many_to_one, :webhook, :class => "PactBroker::Repositories::Webhook", :key => :webhook_id, :primary_key => :id)

      def self.from_model name, value, webhook_id
        db_header = new
        db_header.name = name
        db_header.value = value
        db_header.webhook_id = webhook_id
        db_header
      end

    end
  end
end