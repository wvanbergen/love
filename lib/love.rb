require 'uri'
require 'net/https'
require 'active_support/core_ext/module/attribute_accessors.rb'
require 'yajl'

module Love

  # Create a custom exception class.
  class Exception < StandardError; end
  
  # Class for unauthorized exceptions
  class Unauthorized < Love::Exception; end
  
  
  def self.connect(account, api_key, options = {})
    Love::Client.new(account, api_key, options)
  end
  
  mattr_accessor :logger

  module ResourceURI
    def collection_uri(input)
      case input.to_s
      when /^[\w-]+$/
        ::URI.parse("https://api.tenderapp.com/#{account}/#{input}")
      when %r[^https?://api\.tenderapp\.com/#{account}/[\w-]+]
        ::URI.parse(input.to_s)
      else
        raise Love::Exception, "This does not appear to be a valid Tender category URI!"
      end
    end
  
    def singleton_uri(input, kind)
      case input.to_s
      when /^\d+/
        ::URI.parse("https://api.tenderapp.com/#{account}/#{kind}/#{input}")
      when %r[^https?://api\.tenderapp\.com/#{account}/#{kind}/\d+]
        ::URI.parse(input.to_s)
      else
        raise Love::Exception, "This does not appear to be a Tender #{kind} URI or ID!"
      end
    end
  end
    
  class Client
    
    include Love::ResourceURI

    attr_reader :account
    attr_reader :api_key

    attr_accessor :sleep_between_requests

    def initialize(account, api_key, options = {})
      @account, @api_key = account, api_key
    
      # Handle options
      @sleep_between_requests = options[:sleep_between_requests] || 0.5
    end
  
    def get_user(id_or_href, options = {})
      get(singleton_uri(id_or_href, 'users'))
    end
  
    def get_discussion(id_or_href, options = {})
      get(singleton_uri(id_or_href, 'discussions'))
    end
  
    def get_category(id_or_href, options = {})
      get(singleton_uri(id_or_href, 'categories'))
    end
  
    def get_queue(id_or_href, options = {})
      get(singleton_uri(id_or_href, 'queues'), options)
    end
  
    def each_category(options = {}, &block)
      buffered_each(collection_uri('categories'), 'categories', options, &block)
    end

    def each_queue(options = {}, &block)
      buffered_each(collection_uri('queues'), 'named_queues', options, &block)
    end
  
    def each_user(options = {}, &block)
      buffered_each(collection_uri('users'), 'users', options, &block)
    end
  
    def each_discussion(options = {}, &block)
      buffered_each(collection_uri('discussions'), 'discussions', options, &block)
    end
  
    protected
  
    def get(uri)
      Love.logger.debug "GET #{url}" if Love.logger

      http = Net::HTTP.new(uri.host, uri.port)
      if uri.scheme = 'https'
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      
      req = Net::HTTP::Get.new(uri.request_uri, {
        "Accept"        => "application/vnd.tender-v1+json",
        "X-Tender-Auth" => api_key
      })

      response = http.request(req)
      case response.code
      when /^2\d\d/
        converter = Encoding::Converter.new('binary', 'utf-8', :invalid => :replace, :undef => :replace)
        Yajl::Parser.new.parse(converter.convert(response.body))
      when '401'
        raise Love::Unauthorized, "Invalid credentials used!"
      else
        raise Love::Exception, "#{response.code}: #{response.body}"
      end
    end
  
    def buffered_each(uri, list_key, options = {}, &block)
      query_options = {}
      query_options[:since] = options[:since].to_date.to_s(:db) if options[:since]

      initial_result = get(path, :query => query_options)
      start_page = [options[:start_page].to_i, 1].max rescue 1
      max_page   = (initial_result['total'].to_f / initial_result['per_page'].to_f).ceil
      end_page   = options[:end_page].nil? ? max_page : [options[:end_page].to_i, max_page].min
    
      # Print out some initial debugging information
      Love.logger.debug "Paged requests to #{path}: #{max_page} total pages, importing #{start_page} upto #{end_page}." if Love.logger
    
      start_page.upto(end_page) do |page|
        uri.query = query_options.map { |k, v| "#{k}=#{v}" }.join('&')
        result = get(uri)
        result[list_key].each { |record| yield(record) }
        sleep(sleep_between_requests) if sleep_between_requests
      end
    end
  end
end
