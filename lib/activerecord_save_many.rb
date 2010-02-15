require 'set'

module ActiveRecord
  module SaveMany
    class << self
      attr_accessor :default_max_rows
    end
    self.default_max_rows = 50000

    module ClassMethods
      MAX_QUERY_SIZE = 1024 * 1024
      OPTIONS_KEYS = [:columns, :max_rows, :insert_delayed, :ignore, :update, :updates].to_set

      def save_many_max_rows=(max_rows)
        @save_many_max_rows=max_rows
      end

      def save_many_max_rows
        @save_many_max_rows || ActiveRecord::SaveMany::default_max_rows
      end

      def disable_delayed_insert?
        # for predictable tests we disable delayed insert during testing
        RAILS_ENV=="test" if defined? RAILS_ENV
      end

      def check_options(options)
        unknown_keys = options.keys.to_set - OPTIONS_KEYS.to_set
        raise "unknown options: #{unknown_keys.join(", ")}" if !unknown_keys.empty?
      end

      # slice an array into smaller arrays with maximum size max_size
      def slice_array(max_length, arr)
        slices = []
        (0..arr.length-1).step( max_length ){ |i| slices << values.slice(i,max_length) }
        slices
      end

      def save_many(values, options={} )
        check_options(options)
        return if values.nil? || values.empty?

        columns = options[:columns] || self.columns.map(&:name)

        # add a :type column automatically for STI, if not already present
        if self.superclass!=ActiveRecord::Base && !columns.include?(:type)
          columns = [:type, *columns]
          values = values.map{|vals| [to_s, *vals]}
        end

        # if more than max_rows, execute multiple sql statements
        max_rows = options[:max_rows] || save_many_max_rows
        batches = slice_array(max_rows, values)

        column_list = columns.join(', ')
        do_updates = options[:update] || options[:updates]
        updates = options[:updates] || {}

        batches.each do |batch|
          batch = batch.map do |obj|
            if obj.is_a? ActiveRecord::Base
              obj.send( :callback, :before_save )
              if obj.id
                obj.send( :callback, :before_update)
              else
                obj.send( :callback, :before_create )
              end
              raise "#{obj.errors.full_messages.join(', ')}" if !obj.valid?
            end
            columns.map{|col| obj[col]}
          end

          insert_stmt = options[:insert_delayed] && !disable_delayed_insert? ? "insert delayed" : "insert"
          ignore_opt = options[:ignore] ? "ignore" : ""
          
          sql = "#{insert_stmt} #{ignore_opt} into #{table_name} (#{column_list}) values " + 
            batch.map{|vals| "(" + vals.map{|v| quote_value(v)}.join(", ") +")"}.join(", ") +
            (" on duplicate key update " + columns.map{|c| updates[c] || " #{c} = values(#{c}) "}.join(", ") if do_updates)

          connection.execute_raw sql
        end
      end
    end
  end

  class Base
    class << self
      include ActiveRecord::SaveMany::ClassMethods
    end
  end
end
