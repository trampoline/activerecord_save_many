require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

module ActiveRecord
  describe SaveMany do
    def new_anon_class(parent, &proc)
      klass = Class.new(parent)  
      klass.class_eval(&proc) if proc
      klass
    end

    def new_named_class(parent, name="", &proc)
      new_anon_class(parent) do
        mc=self.instance_eval{ class << self ; self ; end }
        mc.send(:define_method, :to_s){name}
        self.class_eval(&proc) if proc
      end
    end

    # create a new anonymous ActiveRecord::Base descendant class
    def new_ar_class(name="", &proc)
      new_named_class(ActiveRecord::Base, name, &proc)
    end

    describe SaveMany::Functions do
      describe "disable_async?" do
        it "should disable async inserts when testing" do
          mock(SaveMany::Functions).rails_env{"test"}
          SaveMany::Functions::disable_async?.should == true
        end

        it "should permit async inserts when not testing" do
          mock(SaveMany::Functions).rails_env{"production"}
          SaveMany::Functions::disable_async?.should == false
        end
      end

      describe "check_options" do
        it "should raise if given unknown options" do
          lambda do
            SaveMany::Functions::check_options(ActiveRecord::SaveMany::OPTIONS_KEYS, :foo=>100)
          end.should raise_error(RuntimeError)
        end
      end

      describe "slice_array" do
        it "should slice arrays without losing bits" do
          SaveMany::Functions::slice_array(2,[]).should ==([])
          SaveMany::Functions::slice_array(2,[1]).should ==([[1]])
          SaveMany::Functions::slice_array(2,[1,2]).should ==([[1,2]])
          SaveMany::Functions::slice_array(2,[1,2,3]).should ==([[1,2],[3]])
          SaveMany::Functions::slice_array(2,[1,2,3,4]).should ==([[1,2],[3,4]])
        end
      end

      describe "add_columns" do
        it "should add a type column to an indirect inheritor of ActiveRecord::Base" do
          klass = new_named_class(new_ar_class("Foo"), "Bar")
          columns, values = SaveMany::Functions::add_columns(klass, [["foo"]], :columns=>[:foo])
          columns.should == [:type, :foo]
          values.should == [["Bar", "foo"]]
        end

        it "should not add a type column if already present" do
          klass = new_named_class(new_ar_class("Foo"), "Bar")
          columns, values = SaveMany::Functions::add_columns(klass, [["foo", "Baz"]], :columns=>[:foo, :type])
          columns.should == [:foo, :type]
          values.should == [["foo", "Baz"]]
        end

        it "should not add a type column to a direct inheritor of ActiveRecord::Base" do
          klass = new_ar_class("Foo")
          columns, values = SaveMany::Functions::add_columns(klass, [["foo"]], :columns=>[:foo])
          columns.should == [:foo]
          values.should == [["foo"]]
        end
      end
    end

    it "creates a save_many method on an ActiveRecord class" do
      klass = new_ar_class()
      klass.respond_to?(:save_many).should be(true)
    end

    it "should have per-class configurable save_many_max_rows" do
      k1 = new_ar_class()
      k2 = new_ar_class()
      k1.save_many_max_rows=1000
      k2.save_many_max_rows=2000

      k1.save_many_max_rows.should == 1000
      k2.save_many_max_rows.should == 2000
    end

    it "should have a global configurable default_max_rows" do
      k1 = new_ar_class()
      k2 = new_ar_class()
      ActiveRecord::SaveMany::default_max_rows = 100
      k1.save_many_max_rows.should == 100
      k2.save_many_max_rows.should == 100
    end

    # argh. am i really testing the correct sql is generated ?
    describe "save_many" do
      def new_ar_stub(classname, column_names, tablename, match_sql)
        k=new_ar_class(classname)
        stub(k).table_name{tablename}
        cns = column_names.map{|cn| col=Object.new ; stub(col).name{cn} ; col}
        stub(k).columns{cns}
        stub(k).quote_value{|v| "'#{v}'"}
        connection = ActiveRecord::ConnectionAdapters::MysqlAdapter.new
        stub(connection).execute_raw{|sql| 
          sql.should == match_sql
        }
        stub(k).connection{connection}
        k
      end

      def new_ar_inst(klass, id, valid, field_hash)
        kinst = klass.new
        mock(kinst).id(){id}
        mock(kinst).callback(:before_save)
        if id
          mock(kinst).callback(:before_update)
        else
          mock(kinst).callback(:before_create)
        end
        mock(kinst).valid?(){valid}

        field_hash.keys.each{ |key|
          mock(kinst).[](key){field_hash[key]}
        }
        kinst
      end

      it "should generate extended insert sql for all model columns with new objects" do
        k=new_ar_stub("Foo", [:foo, :bar], "foos", "insert into foos (foo,bar) values ('foofoo','barbar')")
        kinst = new_ar_inst(k, nil, true, {:foo=>"foofoo", :bar=>"barbar"})
        k.save_many([kinst])
      end

      it "should generate extended insert sql for all model columns with existing objects" do
        k=new_ar_stub("Foo", [:id, :foo, :bar], "foos", "insert into foos (id,foo,bar) values ('100','foofoo','barbar')")
        kinst = new_ar_inst(k, '100', true, {:foo=>"foofoo", :bar=>"barbar", :id=>'100'})
        k.save_many([kinst])
      end

      it "should generate extended insert sql for all model columns for multiple model instances" do
        k=new_ar_stub("Foo", [:foo, :bar], "foos", 
                      "insert into foos (foo,bar) values ('foofoo','barbar'),('foofoofoo','barbarbar')")
        kinst = new_ar_inst(k, nil, true, {:foo=>"foofoo", :bar=>"barbar"})
        kinst2 = new_ar_inst(k, nil, true, {:foo=>"foofoofoo", :bar=>"barbarbar"})
        k.save_many([kinst,kinst2])
      end

      it "should generate simple extended insert sql for specified columns" do
        k=new_ar_stub("Foo", [:foo, :bar], "foos", "insert into foos (foo) values ('foofoo')")
        kinst = new_ar_inst(k, nil, true, {:foo=>"foofoo"})
        k.save_many([kinst], :columns=>[:foo])
      end

      it "should generate simple extended insert sql for specified string-name columns" do
        k=new_ar_stub("Foo", ["foo", "bar"], "foos", "insert into foos (foo) values ('foofoo')")
        kinst = new_ar_inst(k, nil, true, {"foo"=>"foofoo"})
        k.save_many([kinst], :columns=>["foo"])
      end

      it "should generate insert delayed sql if :async param give " do
        k=new_ar_stub("Foo", [:foo], "foos", "insert delayed into foos (foo) values ('foofoo')")
        kinst = new_ar_inst(k, nil, true, {"foo"=>"foofoo"})
        k.save_many([kinst], :columns=>["foo"], :async=>true)
      end

      it "should generate insert ignore sql if :ignore param given" do
        k=new_ar_stub("Foo", [:foo], "foos", "insert ignore into foos (foo) values ('foofoo')")
        kinst = new_ar_inst(k, nil, true, {"foo"=>"foofoo"})
        k.save_many([kinst], :columns=>["foo"], :ignore=>true)
      end

      it "should generate update sql with all columns if :update given" do
        k=new_ar_stub("Foo", [:foo], "foos", 
                      "insert into foos (foo) values ('foofoo') on duplicate key update foo=values(foo)")
        kinst = new_ar_inst(k, nil, true, {"foo"=>"foofoo"})
        k.save_many([kinst], :columns=>["foo"], :update=>true)
      end

    end

  end
end
