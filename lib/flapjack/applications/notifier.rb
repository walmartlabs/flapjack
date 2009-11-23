#!/usr/bin/env ruby 

require 'log4r'
require 'log4r/outputter/syslogoutputter'
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'patches'))

module Flapjack
  module Notifier
    class Application
     
      # boots the notifier
      def self.run(options={})
        app = self.new(options)
        app.setup_config
        app.setup_loggers
        app.setup_notifiers
        app.setup_recipients
        app.setup_queues

        app
      end

      attr_accessor :log, :recipients

      def initialize(options={})
        @log = options[:logger]
        @notifier_directories = options[:notifier_directories]
        @options = options
      end

      def setup_loggers
        unless @log
	        @log = Log4r::Logger.new("notifier")
	        @log.add(Log4r::StdoutOutputter.new("notifier"))
	        @log.add(Log4r::SyslogOutputter.new("notifier"))
        end
      end

      def setup_config
        @config = OpenStruct.new(@options)
      end

      def setup_notifiers
        @notifier_directories ||= []

        default_directory = File.expand_path(File.join(File.dirname(__FILE__), '..', 'notifiers'))
        # the default directory should be the last in the list
        if @notifier_directories.include?(default_directory)
          @notifier_directories << @notifier_directories.delete(default_directory)
        else
          @notifier_directories << default_directory
        end
     
        # filter to the directories that actually exist
        @notifier_directories = @notifier_directories.find_all do |dir|
          if File.exists?(dir)
            true
          else
            @log.warning("Notifiers directory #{dir} doesn't exist. Skipping.")
            false
          end
        end

        @notifiers = []
      
        # load up the notifiers and pass a config
        @config.notifiers.each_pair do |notifier, config|
          filenames = @notifier_directories.map {|dir| File.join(dir, notifier.to_s, 'init' + '.rb')}
          filename = filenames.find {|filename| File.exists?(filename)}

          if filename
            @log.info("Loading the #{notifier.to_s.capitalize} notifier (from #{filename})")
            require filename
            notifier = Flapjack::Notifiers.const_get("#{notifier.to_s.capitalize}").new(config)
            @notifiers << notifier
          else
            @log.warning("Flapjack::Notifiers::#{notifier.to_s.capitalize} doesn't exist!")
          end
        end

      end

      def setup_recipients
        @recipients ||= []
       
        # load from a file
        if @config.recipients && @config.recipients[:filename]
          @log.info("Loading recipients from #{@config.recipients[:filename]}")
          @recipients += YAML::load(File.read(@config.recipients[:filename]))
        end

        # merge in user specified list
        if @config.recipients && @config.recipients[:list]
          @recipients += @config.recipients[:list]
        end

        # so poking at a recipient within notifiers is easier
        @recipients.map! do |recipient|
          OpenStruct.new(recipient)
        end
      end

      def setup_queues
        defaults = { :type => :beanstalkd, 
                     :host => 'localhost', 
                     :port => '11300',
                     :queue_name => 'results',
                     :log => @log }
        config = defaults.merge(@config.queue_backend || {})
        basedir = config.delete(:basedir) || File.join(File.dirname(__FILE__), '..', 'queue_backends')

        @log.info("Loading the #{config[:type].to_s.capitalize} queue backend")
        
        filename = File.join(basedir, "#{config[:type]}.rb")

        begin 
          require filename
          @results_queue = Flapjack::QueueBackends.const_get("#{config[:type].to_s.capitalize}").new(config)
        rescue LoadError => e
          @log.warning("Attempted to load #{config[:type].to_s.capitalize} queue backend, but it doesn't exist!")
          @log.warning("Exiting.")
          raise # preserves original exception logging
        end
      end

      def process_result
        @log.debug("Waiting for new result...")
        result = @results_queue.next # this blocks until a result is popped
        
        @log.info("Processing result for check #{result.id}.")
        if result.warning? || result.critical?
          if result.any_parents_failed?
            @log.info("Not notifying on check '#{result.id}' as parent is failing.")
          else
            @log.info("Notifying on check '#{result.id}'")
            @notifier_engine.notify!(result)
          end
        end

        @log.info("Storing status of check.")
        result.save

        @log.info("Deleting result for check #{result.id}.")
        @results_queue.delete(result)
      end

      def main_loop
        @log.info("Booting main loop.")
        loop do 
          process_result
        end
      end

    end
  end
end