require "ruboty"
require "ruboty/twitter_search/query"
require "ruboty/twitter_search/statuses_view"
require "twitter"

module Ruboty
  module Handlers
    class TwitterSearch < Base
      NAMESPACE = "twitter-search"
      TWEETS_COUNT = 10

      env :TWITTER_ACCESS_TOKEN, "Twitter access token"
      env :TWITTER_ACCESS_TOKEN_SECRET, "Twitter access token secret"
      env :TWITTER_CONSUMER_KEY, "Twitter consumer key (a.k.a. API key)"
      env :TWITTER_CONSUMER_SECRET, "Twitter consumer secret (a.k.a. API secret)"
      env :TWITTER_DISABLE_SINCE_ID, "Pass 1 to disable using since_id parameter", optional: true

      on(
        /search twitter by (?<query>.+)/,
        description: "Search twitter by given query",
        name: :search,
      )

      on(
        /ignore twitter user (?<screen_name>.+)\z/,
        name: "ignore",
        description: "Ignore twitter user",
      )

      on(
        /list ignore twitter users\z/,
        name: "list",
        description: "List all ignore twitter users",
      )

      # @return [true] to prevent running missing handlers.
      def search(message)
        query = Ruboty::TwitterSearch::Query.new(message[:query])

        statuses = client.search(
          query.query_string,
          result_type: query.result_type,
          since_id: fetch_since_id_for(message[:query]),
        ).take(TWEETS_COUNT)

        since_id = statuses.first.id

        statuses.select! do |status|
          status.retweet_count >= query.minimum_retweet_count
        end

        statuses.select! do |status|
          status.favorite_count >= query.minimum_favorite_count
        end

        statuses.reject! do |status|
          ignore_users.include?(status.user.screen_name)
        end

        if statuses.any?
          message.reply(Ruboty::TwitterSearch::StatusesView.new(statuses).to_s)
          store_since_id(query: message[:query], since_id: since_id)
        end
      rescue ::Twitter::Error => exception
        message.reply("#{exception.class}: #{exception}")
      ensure
        return true
      end

      def ignore(message)
        ignore_users << message[:screen_name]
        message.reply("Ignored twitter user: #{message[:screen_name]}")
      end

      def list(message)
        message.reply(ignore_users, code: true)
      end

      private

      def client
        @client ||= ::Twitter::REST::Client.new do |config|
          config.consumer_key = ENV["TWITTER_CONSUMER_KEY"]
          config.consumer_secret = ENV["TWITTER_CONSUMER_SECRET"]
          config.access_token = ENV["TWITTER_ACCESS_TOKEN"]
          config.access_token_secret = ENV["TWITTER_ACCESS_TOKEN_SECRET"]
        end
      end

      def disabled_to_use_since_id?
        ENV["TWITTER_DISABLE_SINCE_ID"] == "1"
      end

      # @param query [String] Query string to be passed to Twitter API
      # @return [Integer, nil] since_id or nil
      def fetch_since_id_for(query)
        unless disabled_to_use_since_id?
          store[query]
        end
      end

      # @note To remember since_id for each query.
      def store
        robot.brain.data[NAMESPACE] ||= {}
      end

      def store_since_id(query: nil, since_id: nil)
        unless disabled_to_use_since_id?
          store[query] = since_id
        end
      end

      def store_ignore_users
        store[:ignore_users] ||= []
      end

      def ignore_users
        @ignore_users ||= store_ignore_users
      end
    end
  end
end
