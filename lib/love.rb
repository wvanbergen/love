require 'uri'
require 'cgi'
require 'net/https'
require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/hash/keys'
require 'yajl'

# Love is a small Ruby library to interact with the Tender REST API.
# The main object to work with is {Love::Client}, which is returned
# by calling {Love.connect}.
#
# It is dedicated to the awesome work Aaeron Patterson has been giving
# to the Ruby community.
module Love

  # The current gem version. Will be updated automatically by the gem
  # release script.
  VERSION = "0.0.5"

  # Exception class a custom exception class.
  class Exception < StandardError; end
  
  # Exception class for unauthorized requests or resources that are forbidden
  class Unauthorized < Love::Exception; end
  
  # Exception class for resources that are not found
  class NotFound < Love::Exception; end
  
  
  # Connects to the Tender API to access a site using an API key.
  #
  # This method doesn't do any communication yet with the Tender API, it will
  # only set up the client with the provided credentials and options.
  #
  # By default, the client will use a new connection for every request. It can also
  # open a persistent connection if you want to do multiple requests, by passing
  # <tt>:persistent => true</tt> as option. In this case, you need to call {Love::Client#close_connection}
  # when you are done with your session. You can also provide a block to this method
  # which will automatically open up a persistent connection and close it at the end
  # of the block.
  #
  # @param (see Love::Client#initialize)
  # @option (see Love::Client#initialize)  
  # @overload connect(site, api_key, options = {}) { ... }
  #   @yield [Love::Client] An API client to work with using a persistent connection.
  #   @return The return value of the block. The persistent connection will be closed
  # @overload connect(site, api_key, options = {})
  #   @return [Love::Client] An API client to work with. By default, the returned
  #     client will not use a persistent TCP connection, so a new connection will
  #     be
  # @see Love::Client#initialize
  def self.connect(site, api_key, options = {}, &block)
    if block_given?
      begin
        client = Love::Client.new(site, api_key, options.merge(:persistent => true))
        block.call(client)
      ensure
        client.close_connection
      end
    else
      Love::Client.new(site, api_key, options)
    end
  end
  
  # @return [Logger] Set this attribute to a Logger instance to log the
  # HTTP connectivity somewhere.
  mattr_accessor :logger

  # Module to work with Tender REST URIs.
  module ResourceURI
    
    # Returns a collection URI, based on an URI instance, a complete URI string or just a resource name.
    # @return [URI] The URI on which the REST resource collection is accessible through the Tender REST API.
    # @raise [Love::Exception] If the input cannot be converted into a resource collection URI.
    def collection_uri(input)
      case input.to_s
      when /^[\w-]+$/
        ::URI.parse("https://api.tenderapp.com/#{site}/#{input}")
      when %r[^https?://api\.tenderapp\.com/#{site}/[\w-]+]
        ::URI.parse(input.to_s)
      else
        raise Love::Exception, "This does not appear to be a valid Tender category URI!"
      end
    end

    # Returns a resource URI, based on an URI instance, a complete URI string or just a resource ID.
    # @param [Object input The complete URI or just resource ID as URI, String or Integer.
    # @param [String] kind The kind of resource.
    # @return [URI] The URI on which the REST resource  is accessible through the Tender REST API.
    # @raise [Love::Exception] If the input cannot be converted into a resource URI.
    def singleton_uri(input, kind)
      case input.to_s
      when /^\d+/
        ::URI.parse("https://api.tenderapp.com/#{site}/#{kind}/#{input}")
      when %r[^https?://api\.tenderapp\.com/#{site}/#{kind}/\d+]
        ::URI.parse(input.to_s)
      else
        raise Love::Exception, "This does not appear to be a Tender #{kind} URI or ID!"
      end
    end
    
    # Appends GET parameters to a URI instance. Duplicate parameters will
    # be replaced with the new value.
    # @param [URI] base_uri The original URI to work with (will not be modified)
    # @param [Hash] added_params To GET params to add.
    # @return [URI] The URI with appended GET parameters
    def append_query(base_uri, added_params = {})
      base_params = base_uri.query ? CGI.parse(base_uri.query) : {}
      get_params = base_params.merge(added_params.stringify_keys)
      base_uri.dup.tap do |uri|
        assignments = get_params.map do |k, v|
          case v
            when Array; v.map { |val| "#{::CGI.escape(k.to_s)}=#{::CGI.escape(val.to_s)}" }.join('&')
            else "#{::CGI.escape(k.to_s)}=#{::CGI.escape(v.to_s)}"
          end
        end
        uri.query = assignments.join('&')
      end
    end
  end
  
  # The Love::Client class acts as a client to the Tender REST API. Obtain an instance of this
  # class by calling {Love.connect} instead of instantiating this class directly. 
  #
  # You can either fetch individual resources using {#get_user}, {#get_discussion}, and
  # similar methods, or iterate over collections using {#each_discussion}, {#each_category}
  # and similar methods.
  class Client
    
    # The Tender API host to connect to.
    TENDER_API_HOST = 'api.tenderapp.com'
    
    include Love::ResourceURI

    # @return [String] The site to work with
    attr_reader :site
    
    # @return [String] The API key to authenticate with.
    attr_reader :api_key

    # @return [Float] The number of seconds to sleep between paged requests.
    attr_accessor :sleep_between_requests

    # Initializes the client.
    # @param [String] site The site to work with.
    # @param [String] api_key The API key for this site.
    # @param [Hash] options Connectivity options.
    # @option options [Boolean] :persistent (false) Whether to create a persistent TCP connection.
    # @option options [Float] :sleep_between_requests (0.5) The time between requests in seconds.
    # @see Love.connect
    def initialize(site, api_key, options = {})
      @site, @api_key = site, api_key
    
      # Handle options
      @persistent = !!options[:persistent]
      @sleep_between_requests = options[:sleep_between_requests] || 0.5
    end
  
    # Returns a single Tender user.
    # @param [URI, String, Integer] id_or_href The user ID or HREF. Can be either a URI
    #   instance, a string containing a URI, or a user ID as a numeric string or integer.
    # @return [Hash] The user attributes in a Hash.
    def get_user(id_or_href)
      get(singleton_uri(id_or_href, 'users'))
    end

    # Returns a single Tender discussion.
    # @param [URI, String, Integer] id_or_href The discussion ID or HREF. Can be either a URI
    #   instance, a string containing a URI, or a discussion ID as a numeric string or integer.
    # @return [Hash] The discussion attributes in a Hash.
    def get_discussion(id_or_href)
      get(singleton_uri(id_or_href, 'discussions'))
    end
  
    # Returns a single Tender category.
    # @param [URI, String, Integer] id_or_href The category ID or HREF. Can be either a URI
    #   instance, a string containing a URI, or a category ID as a numeric string or integer.
    # @return [Hash] The category attributes in a Hash.
    def get_category(id_or_href)
      get(singleton_uri(id_or_href, 'categories'))
    end
  
    # Returns a single Tender queue.
    # @param [URI, String, Integer] id_or_href The queue ID or HREF. Can be either a URI
    #   instance, a string containing a URI, or a queue ID as a numeric string or integer.
    # @return [Hash] The queue attributes in a Hash.
    def get_queue(id_or_href)
      get(singleton_uri(id_or_href, 'queues'), options)
    end

    # Iterates over all Tender categories.
    # @yield [Hash] The attributes of each category will be yielded as (nested) Hash.
    # @option (see #paged_each)
    # @return [nil]
    def each_category(options = {}, &block)
      paged_each(collection_uri('categories'), 'categories', options, &block)
    end

    # Iterates over all Tender users.
    # @yield [Hash] The attributes of each user will be yielded as (nested) Hash.
    # @option (see #paged_each)
    # @return [nil]
    def each_queue(options = {}, &block)
      paged_each(collection_uri('queues'), 'named_queues', options, &block)
    end
  
    # Iterates over all Tender users.
    # @yield [Hash] The attributes of each user will be yielded as (nested) Hash.
    # @option (see #paged_each)
    # @return [nil]
    def each_user(options = {}, &block)
      paged_each(collection_uri('users'), 'users', options, &block)
    end
  
    # Iterates over all Tender discussions.
    # @yield [Hash] The attributes of each discussion will be yielded as (nested) Hash.
    # @option (see #paged_each)
    # @return [nil]
    def each_discussion(options = {}, &block)
      paged_each(collection_uri('discussions'), 'discussions', options, &block)
    end
    
    # Returns a persistent connection to the server, reusing a connection of it was
    # previously established. 
    #
    # This method is mainly used for internal use but can be used to do advanced 
    # HTTP connectivity with the Tender API server.
    #
    # @return [Net::HTTP] The net/http connection instance.
    def connection
      @connection ||= Net::HTTP.new(TENDER_API_HOST, Net::HTTP.https_default_port).tap do |http|
        http.use_ssl = true
        # http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        http.start
      end
    end
    
    # Closes the persistent connectio  to the server
    # @return [nil]
    def close_connection
      @connection.finish if connected?
    end

    # @return [Boolean] <tt>true</tt> iff the client currently has a TCP connection with the Tender API server.
    def connected?
      @connection && @connection.started?
    end
    
    # @return [Boolean] <tt>true</tt> iff the client is using persistent connections.
    def persistent?
      @persistent
    end
  
    protected
    
    def request_headers
      @request_headers ||=  { "Accept" => "application/vnd.tender-v1+json", "X-Tender-Auth" => api_key }
    end
  
    def get(uri)
      raise Love::Exception, "This is not a Tender API URI." unless uri.host = TENDER_API_HOST

      Love.logger.debug "GET #{uri.request_uri}" if Love.logger
      
      request  = Net::HTTP::Get.new(uri.request_uri, request_headers)
      response = connection.request(request)
      case response
        when Net::HTTPSuccess;      Yajl::Parser.new.parse(safely_convert_to_utf8(response.body))
        when Net::HTTPUnauthorized; raise Love::Unauthorized, "Invalid credentials used!"
        when Net::HTTPForbidden;    raise Love::Unauthorized, "You don't have permission to access this resource!"
        when Net::NotFound;         raise Love::NotFound, "The resource #{uri} was not found!"
        else raise Love::Exception, "#{response.code}: #{response.body}"
      end
    ensure 
      close_connection unless persistent?
    end
  
    # Converts a binary, (alomst) UTF-8 string into an actual UTF-8 string.
    # It will replace any unknown characters or unvalid byte sequences into a UTF-8
    # "unknown character" question mark.
    #
    # @param [String] binary_string The input string, should have binary encoding
    # @return [String] The string using UTF-8 encoding.
    def safely_convert_to_utf8(binary_string)
      if binary_string.respond_to?(:force_encoding)
        # Ruby 1.9
        converter = Encoding::Converter.new('binary', 'utf-8', :invalid => :replace, :undef => :replace)
        converter.convert(binary_string)
      else
        # Ruby 1.8 - currently don't do anything
        binary_string
      end
    end
  
    # Iterates over a collection, issuing multiple requests to get all the paged results.
    #
    # @option options [Date] :since Only include records updated since the provided date.
    #   Caution: not supported by all resources.
    # @option options [Integer] :start_page The initial page number to request.
    # @option options [Integer] :end_page The final page number to request.
    def paged_each(uri, list_key, options = {}, &block)
      query_params = {}
      query_params[:since] = options[:since].to_date.to_s(:db) if options[:since]
      query_params[:page]  = [options[:start_page].to_i, 1].max rescue 1
      
      initial_result = get(append_query(uri, query_params))
      
      # Determine the amount of pages that is going to be requested.
      max_page = (initial_result['total'].to_f / initial_result['per_page'].to_f).ceil
      end_page = options[:end_page].nil? ? max_page : [options[:end_page].to_i, max_page].min
    
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
        result = get(append_query(uri, query_params))
        if result[list_key].kind_of?(Array)
          result[list_key].each { |record| yield(record) }
          sleep(sleep_between_requests) if sleep_between_requests
        end
      end
    end
  end
end
