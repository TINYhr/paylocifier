require 'faraday'
require 'base64'
require 'json'

require_relative 'encryption'

class Faraday::Request::Multipart < Faraday::Request::UrlEncoded
  def create_multipart(env, params)
    boundary = env.request.boundary
    parts = process_params(params) do |key, value|
      if (JSON.parse(value) rescue false)
        Faraday::Parts::Part.new(boundary, key, value, 'Content-Type' => 'application/json')
      else
        Faraday::Parts::Part.new(boundary, key, value)
      end
    end
    parts << Faraday::Parts::EpiloguePart.new(boundary)

    body = Faraday::CompositeReadIO.new(parts)
    env.request_headers[Faraday::Env::ContentLength] = body.length.to_s
    return body
  end
end

class Paylocifier::Client
  attr_reader :config

  def initialize
    @config = Paylocifier.config
  end

  def post(url, data, legacy: false)
    send_request(:post, url, data, legacy: legacy)
  end

  def put(url, data, legacy: false)
    send_request(:put, url, data, legacy: legacy)
  end

  def delete(url, legacy: false)
    conn = legacy ? legacy_connection : connection
    parse_response(conn.delete(url.to_s))
  end

  def send_request(method, url, data, legacy: false)
    conn = if url == 'deduction'
      legacy_deduction_connection
    elsif legacy
      legacy_connection
    else
      connection
    end

    body = config.encryption ? Paylocifier::Encryption.encode(data) : data

    parse_response(conn.send(method, url.to_s) do |req|
      req.body = body.to_json
    end)
  end

  def get(url, legacy: false)
    conn = legacy ? legacy_connection : connection
    parse_response(conn.get(url.to_s))
  end

  def refresh_token!
    conn = Faraday.new(url: config.host.gsub(%r(/?api/v2/?), ''))
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

    parse_response(resp)['access_token']
  end

  def refresh_payroll_token!
    conn = Faraday.new(url: config.payroll_token_endpoint)
    resp = conn.post('public/security/v1/token') do |req|
      req.body = {
        grant_type:     'client_credentials',
        scope:          'all',
        client_id:      config.payroll_client_id,
        client_secret:  config.payroll_secret
      }
      req.headers = {
        'Content-Type':   'application/x-www-form-urlencoded',
        # 'Authorization':  "Basic #{ payroll_oauth_token }"
      }
    end

    parse_response(resp)['access_token']
  end

  def fetch_secret
    # conn = Faraday.new(url: config.host)
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

  def payroll_connection
    token = refresh_payroll_token!
    url = "#{ config.payroll_host }/companies/#{ config.company_id }/"

    @payroll_connection ||= Faraday.new(url: url) do |faraday|
      faraday.request :multipart
      faraday.request :url_encoded
      faraday.adapter :net_http
      faraday.headers = {
        'Authorization': "Bearer #{ token }"
      }
    end
  end

  private

  def oauth_token
    Base64.strict_encode64("#{ config.client_id }:#{ config.client_secret }")
  end

  def payroll_oauth_token
    Base64.strict_encode64("#{ config.payroll_client_id }:#{ config.payroll_secret }")
  end

  def connection
    token = refresh_token!
    @connection = Faraday.new(
      url:      "#{ config.host }/companies/#{ config.company_id }/",
      headers:  {
        'Content-Type': 'application/json',
        'Authorization': "Bearer #{ token }"
      }
    )
  end

  def legacy_connection
    token = refresh_token!
    @legacy_connection = Faraday.new(
      url:      "#{ config.legacy_host }/companies/#{ config.company_id }/",
      headers:  {
        'Content-Type': 'application/json',
        'Authorization': "Bearer #{ token }"
      }
    )
  end

  def legacy_deduction_connection
    token = refresh_token!
    @legacy_deduction_connection = Faraday.new(
      url:      "#{ config.legacy_host }/",
      headers:  {
        'Content-Type': 'application/json',
        'Authorization': "Bearer #{ token }"
      }
    )
  end

  def parse_response(resp)
    if resp.status.between?(200, 299)
      data = resp.body
      if data.is_a?(String) && data.length > 0
        data = JSON.parse(resp.body)
      elsif data.is_a?(String) && data.length == 0
        return 'Success'
      end

      if data.is_a?(Array)
        data.map { |item| item.deep_transform_keys!(&:underscore) }
      else
        data.deep_transform_keys!(&:underscore)
      end
    elsif resp.status == 429
      raise Paylocifier::TooManyRequestError, "#{ resp.status } - #{ resp.reason_phrase }"
    elsif resp.status == 400
      messages = JSON.parse(resp.body).map { |item| "\t - #{ item['message'] } #{ item['options'] }" }
      messages = messages.join("\n")
      raise "#{ resp.status }:\n\n#{ messages }"
    else
      raise "#{ resp.status } - #{ resp.reason_phrase }"
    end
  end
end
