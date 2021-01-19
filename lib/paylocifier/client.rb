require 'faraday'
require 'base64'
require 'json'

class Paylocifier::Client
  attr_reader :config

  @@access_token = nil

  def initialize
    @config = Paylocifier.config
  end

  def post(url, data)
    parse_response(connection.post(url.to_s, data))
  end

  def get(url)
    parse_response(connection.get(url.to_s))
  end

  def refresh_token!
    conn = Faraday.new(url: 'https://api.paylocity.com/')
    resp = conn.post('IdentityServer/connect/token') do |req|
      req.body = {
        grant_type: 'client_credentials',
        scope:      'WebLinkAPI'
      }
      req.headers = {
        'Content-Type':   'application/x-www-form-urlencoded',
        'Authorization':  "Basic #{ oauth_token }"
      }
    end

    @@access_token = parse_response(resp)['access_token']
  end

  def fetch_secret
    # conn = Faraday.new(url: 'https://api.paylocity.com/')
    # resp = conn.post('IdentityServer/connect/token') do |req|
    #   req.body = {
    #     grant_type: 'client_credentials',
    #     scope:      'WebLinkAPI'
    #   }
    #   req.headers = {
    #     'Content-Type': 'application/x-www-form-urlencoded',
    #     'Authorization': "Basic #{ oauth_token }"
    #   }
    # end

    # @@access_token = parse_response(resp)['access_token']
  end

  private

  def oauth_token
    Base64.strict_encode64("#{ config.client_id }:#{ config.client_secret }")
  end

  def connection
    refresh_token! if @@access_token.nil?
    @connection ||= Faraday.new(
      url:      "#{ config.host }/companies/#{ config.company_id }/",
      headers:  {
        'Content-Type': 'application/json',
        'Authorization': "Bearer #{ @@access_token }"
      }
    )
  end

  def parse_response(resp)
    if resp.status == 200
      data = JSON.parse(resp.body)
      if data.is_a?(Array)
        data.map { |item| item.transform_keys(&:underscore) }
      else
        data.transform_keys(&:underscore)
      end
    else
      raise "#{ resp.status } - #{ resp.reason_phrase }"
    end
  end
end
