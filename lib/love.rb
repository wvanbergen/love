require 'uri'
require 'net/https'
require 'active_support'
require 'yajl'

class Love
  
  # Create a custom exception class.
  class Exception < StandardError; end
  
  # Class for unauthorized exceptions
  class Unauthorized < Love::Exception; end
  
  attr_accessor :logger
  
  attr_reader :account
  attr_reader :api_key

  attr_accessor :sleep_between_requests

  def initialize(account, api_key, options = {})
    @account, @api_key = account, api_key
    
    # Handle options
    @sleep_between_requests = options[:sleep_between_requests] || 0.5
  end
  
  def self.connect(account, api_key, options = {})
    new(account, api_key, options)
  end

  def get_user(id_or_href, options = {})
    if id_or_href.to_s =~ /(\d+)$/
      get("users/#{$1}", options)
    else 
      # TODO: use href
      nil
    end
  end
  
  def get_discussion(id_or_href, options = {})
    if id_or_href.to_s =~ /(\d+)$/
      get("discussions/#{$1}", options)
    else 
      # TODO: use href
      nil
    end
  end
  
  def each_category(options = {}, &block)
    buffered_each('categories', 'categories', options, &block)
  end

  def each_queue(options = {}, &block)
    buffered_each('queues', 'named_queues', options, &block)
  end
  
  def each_user(options = {}, &block)
    buffered_each('users', 'users', options, &block)
  end
  
  def each_discussion(options = {}, &block)
    buffered_each('discussions', 'discussions', options, &block)
  end
  
  protected
  
  def get(path, options = {})
    url = URI.parse("https://api.tenderapp.com/#{account}/#{path}")

    logger.debug "GET #{url.to_s}" if logger

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      
    req = Net::HTTP::Get.new(url.path, {
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
  
  def buffered_each(path, list_key, options = {}, &block)
    query_options = {}
    query_options[:since] = options[:since].to_date.to_s(:db) if options[:since]

    initial_result = get(path, :query => query_options)
    start_page = [options[:start_page].to_i, 1].max rescue 1
    max_page   = (initial_result['total'].to_f / initial_result['per_page'].to_f).ceil
    end_page   = options[:end_page].nil? ? max_page : [options[:end_page].to_i, max_page].min
    
    # Print out some initial debugging information
    logger.debug "Paged requests to #{path}: #{max_page} total pages, importing #{start_page} upto #{end_page}." if logger
    
    start_page.upto(end_page) do |page|
      result = get(path, :query => query_options.merge(:page => page))
      result[list_key].each { |record| yield(record) }
      sleep(sleep_between_requests) if sleep_between_requests
    end
  end
end
