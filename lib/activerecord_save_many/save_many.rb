require 'set'

module ActiveRecord
  module SaveMany
    MAX_QUERY_SIZE = 1024 * 1024
    # options for the create_many method
    OPTIONS_KEYS = [:columns, :max_rows, :replace, :async, :ignore, :update, :updates].to_set

    # options for the save_many_sql method
    SQL_OPTIONS_KEYS = [:replace, :async, :ignore, :update, :updates].to_set

    class << self
      attr_accessor :default_max_rows
    end
    self.default_max_rows = 50000

    module Functions
      def rails_env
        RAILS_ENV if defined? RAILS_ENV
      end
      module_function :rails_env

      def disable_async?
        # for predictable tests we disable delayed insert during testing
        rails_env()=="test"
      end
      module_function :disable_async?

      def check_options(permitted, options)
        unknown_keys = options.keys.to_set - permitted
        raise "unknown options: #{unknown_keys.to_a.join(", ")}" if !unknown_keys.empty?
        raise "can't :replace and :ignore||:update||:async" if options[:replace] && (options[:ignore] || options[:update] || options[:updates] || options[:async])
      end
      module_function :check_options
      
      # slice an array into smaller arrays with maximum size max_size
      def slice_array(max_length, arr)
        slices = []
        (0..arr.length-1).step( max_length ){ |i| slices << arr.slice(i,max_length) }
        slices
      end
      module_function :slice_array

      def add_columns(klass, values, options)
        columns = options[:columns] || klass.columns.map(&:name)

        # add a :type column automatically for STI, if not already present
        if klass.superclass!=ActiveRecord::Base && !columns.include?(:type)
          columns = [:type, *columns]
          values = values.map{|vals| [klass.to_s, *vals]}
        end

        [columns, values]
      end
      module_function :add_columns
    end

    module ClassMethods
      def save_many_max_rows=(max_rows)
        @save_many_max_rows=max_rows
      end

      def save_many_max_rows
        @save_many_max_rows || ActiveRecord::SaveMany::default_max_rows
      end

      def save_many(values, options={})
        Functions::check_options(ActiveRecord::SaveMany::OPTIONS_KEYS , options)
        return if values.nil? || values.empty?

        columns, values = Functions::add_columns(self, values, options)

        # if more than max_rows, execute multiple sql statements
        max_rows = options[:max_rows] || save_many_max_rows
        batches = Functions::slice_array(max_rows, values)

        batches.each do |rows|
          rows = rows.map do |obj|
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

          sql = connection.save_many_sql(self,
                                         table_name, 
                                         columns, 
                                         rows, 
                                         { :replace=>options[:replace],
                                           :ignore=>options[:ignore],
                                           :async=>options[:async] && !Functions::disable_async?(),
                                           :update=>options[:update] || options[:updates],
                                           :updates=>options[:updates] || {} })
          
          connection.execute_raw sql
        end
      end
    end

    module MySQL
      def save_many_sql(klass, table_name, columns, rows, options)
        
        sql = [(if options[:replace] then "replace" else "insert" end), 
               ("delayed" if options[:async]), 
               ("ignore" if options[:ignore])].compact.join(' ') + 
          " into #{table_name} (#{columns.join(',')}) values " + 
          rows.map{|vals| "(" + vals.map{|v| klass.quote_value(v)}.join(",") +")"}.join(",") +
          (" on duplicate key update "+columns.map{|c| options[:updates][c] || "#{c}=values(#{c})"}.join(",") if options[:update]).to_s
      end
    end
  end

  class Base
    class << self
      include ActiveRecord::SaveMany::ClassMethods
    end
  end
end

module JdbcSpec
  module MySQL
    include ActiveRecord::SaveMany::MySQL
  end
end

module ActiveRecord
  module ConnectionAdapters
    class MysqlAdapter
      include ActiveRecord::SaveMany::MySQL
    end
  end
end
