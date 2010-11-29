require 'spec_helper'

describe Love::ResourceURI do
  
  include Love::ResourceURI
  def account; "mysupport"; end
  
  describe '#collection_uri' do

    it "should build a valid URI based on the resource name" do
      collection_uri('foos').should be_kind_of(::URI)
      collection_uri('bars').to_s.should == 'https://api.tenderapp.com/mysupport/bars'
    end
    
    it "should accept a valid URI string" do
      collection_uri('https://api.tenderapp.com/mysupport/bars').should be_kind_of(::URI)
      collection_uri('https://api.tenderapp.com/mysupport/bars').to_s.should == 'https://api.tenderapp.com/mysupport/bars'
    end

    it "should accept a valid URI object" do
      uri = URI.parse('https://api.tenderapp.com/mysupport/bars')
      collection_uri(uri).should be_kind_of(::URI)
      collection_uri(uri).should == uri
    end
    
    it "should not accept a URI for another account" do
      lambda { collection_uri('https://api.tenderapp.com/other/bars') }.should raise_error(Love::Exception)
    end

    it "should not accept an unrelated URI" do
      lambda { collection_uri('http://www.vanbergen.org/mysupport/foos') }.should raise_error(Love::Exception)
    end

    it "should not weird resource names" do
      lambda { collection_uri('%!&') }.should raise_error(Love::Exception)
    end
  end
  
  describe '#singleton_uri' do
    
    it "should build a valid URI based on the resource ID" do
      singleton_uri(123, 'foos').should be_kind_of(::URI)
      singleton_uri('456', 'bars').to_s.should == 'https://api.tenderapp.com/mysupport/bars/456'
    end
    
    it "should accept a valid URI string" do
      singleton_uri('https://api.tenderapp.com/mysupport/foos/123', 'foos').should be_kind_of(::URI)
      singleton_uri('https://api.tenderapp.com/mysupport/bars/456', 'bars').to_s.should == 'https://api.tenderapp.com/mysupport/bars/456'
    end

    it "should accept a valid URI object" do
      uri = URI.parse('https://api.tenderapp.com/mysupport/bars/789')
      singleton_uri(uri, 'bars').should be_kind_of(::URI)
      singleton_uri(uri, 'bars').should == uri
    end    
    
    it "should not accept a URI for another account" do
      lambda { singleton_uri('https://api.tenderapp.com/other/bars/123', 'bars') }.should raise_error(Love::Exception)
    end

    it "should not accept an unrelated URI" do
      lambda { singleton_uri('http://www.vanbergen.org/mysupport/foos', 'foos') }.should raise_error(Love::Exception)
    end

    it "should not weird resource IDs" do
      lambda { singleton_uri('%!&', 'bars') }.should raise_error(Love::Exception)
    end    
  end
end

describe Love::Client do
end
