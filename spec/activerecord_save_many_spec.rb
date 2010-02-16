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
            SaveMany::Functions::check_options(:foo=>100)
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

    
  end
end
