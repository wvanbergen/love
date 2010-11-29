require 'uri'
require 'net/https'
require 'active_support/core_ext/module/attribute_accessors.rb'
require 'yajl'

module Love

  VERSION = "0.0.4"

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
    
    def request_uri(base_uri, added_params = {})
      base_params = base_uri.query ? CGI.parse(base_uri.query) : {}
      get_params = base_params.merge(added_params || {})
      base_uri.dup.tap do |uri|
        uri.query = get_params.map { |k, v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}"}.join('&')
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
      Love.logger.debug "GET #{uri}" if Love.logger

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
      query_params = {}
      query_params[:since] = options[:since].to_date.to_s(:db) if options[:since]
      query_params[:page]  = [options[:start_page].to_i, 1].max rescue 1
      
      initial_result = get(request_uri(uri, query_params))
      
      # Determine the amount of pages that is going to be requested.
      max_page   = (initial_result['total'].to_f / initial_result['per_page'].to_f).ceil
      end_page   = options[:end_page].nil? ? max_page : [options[:end_page].to_i, max_page].min
    
      # Print out some initial debugging information
      Love.logger.debug "Paged requests to #{uri}: #{max_page} total pages, importing #{query_params[:page]} upto #{end_page}." if Love.logger
    
      # Handle first page of results
      if initial_result[list_key].kind_of?(Array)
        initial_result[list_key].each { |record| yield(record) }
        sleep(sleep_between_requests) if sleep_between_requests
      end
    
      start_page = query_params[:page].to_i + 1
      start_page.upto(end_page) do |page|
        query_params[:page] = page
        result = get(request_uri(uri, query_params))
        if result[list_key].kind_of?(Array)
          result[list_key].each { |record| yield(record) }
          sleep(sleep_between_requests) if sleep_between_requests
        end
      end
    end
  end
end
