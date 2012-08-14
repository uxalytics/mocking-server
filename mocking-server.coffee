fs = require 'fs'
url = require 'url'
https = require 'https'
_ = require 'underscore'
{clone, timeoutSet, dictionaries_equal, pretty_json_stringify, match_glob} = require './util'


parse_url = (s) ->
  {protocol, hostname, path} = url.parse s
  if not protocol
    if s.charAt(0) == '/'
      hostname = null
      path = s
    else
      bits = s.split '/'
      hostname = bits[0]
      path = if bits.length > 1 then bits.slice(1).join '/' else null
    if hostname
      hostname = hostname.split(':')[0]
  {hostname, path}


matches_expectation = (req, req_text, expectation) ->
  e = expectation

  if e.method
    return false if req.method != e.method

  if e.url
    {hostname, path} = parse_url e.url
    return false if hostname and hostname != req.headers.host
    return false if path and path != req.url

  if e.req_body
    return false if e.req_body != req_text

  if e.req_body_glob
    return false if not match_glob req_text, e.req_body_glob

  if e.req_headers
    headers = clone req.headers
    delete headers['content-length']
    return false if not dictionaries_equal headers, e.req_headers
  true


find_groups = (text, e) ->
  groups = [text]
  if e.req_body_glob
    m = match_glob text, e.req_body_glob
    for i in [1...m.length]
      groups.push m[i]
  groups


class MockingServer
  constructor: () ->
    @httpLogger = new HTTPLogger
    @expectations = []
    @unexpected_requests = []
    @requests = []

  handleRequest: (req, res) ->
    @httpLogger.requestText req, (req_text) =>
      if req.headers['x-mocking-server'] == 'API'
        @_handleApiRequest req, res, req_text
      else
        reqInfo = {
          text: req_text
          url: req.url
          headers: req.headers
          method: req.method
        }
        @requests.push reqInfo
        for expectation, i in @expectations
          if matches_expectation req, req_text, expectation
            reqInfo.groups = find_groups req_text, expectation
            @expectations = _.without @expectations, expectation
            @_handleExpectedResult req, res, req_text, expectation
            return
        @_handleUnexpectedResult req, res, req_text

  _handleApiRequest: (req, res, req_text) ->
    if req.url == '/mock'
      @expectations.push JSON.parse req_text
      @httpLogger.respond req, res, 200, {}, JSON.stringify {}
    else if req.url == '/clear-expectations'
      unmet_expectations = @expectations
      unexpected_requests = @unexpected_requests
      @httpLogger.respond req, res, 200, {}, JSON.stringify {
        unmet_expectations
        unexpected_requests
        message: pretty_json_stringify {unmet_expectations, unexpected_requests}
      }
      @expectations = []
    else if req.url.match /^\/last-request-matching/
      expectation = JSON.parse req_text
      for i in [(@requests.length - 1)..0]
        reqInfo = @requests[i]
        if matches_expectation reqInfo, reqInfo.text, expectation
          return @httpLogger.respond req, res, 200, {}, JSON.stringify {request:reqInfo}
      @httpLogger.respond req, res, 404, {}, JSON.stringify {}
    else
      @httpLogger.respond req, res, 404, {}, '404'

  _handleExpectedResult: (req, res, req_text, expectation) ->
    {res_body, code, res_headers} = expectation
    res_body or= ''
    res_body = new Buffer res_body, 'utf-8'
    code or= 200
    res_headers or= {}
    res_headers['Content-Length'] = res_body.length
    if expectation.respond != false
      res_delay = if expectation.res_delay? then expectation.res_delay else 0
      timeoutSet (res_delay * 1000), () =>
        @httpLogger.respond req, res, code, res_headers, res_body

  _handleUnexpectedResult: (req, res, req_text) ->
    headers = clone req.headers
    delete headers['content-type']
    @unexpected_requests.push {
      method: req.method
      url: "#{req.headers.host}#{req.url}"
      req_body: req_text
      req_headers: headers
    }
    @httpLogger.respond req, res, 503, {'Content-Type': 'text/plain'}, 'Request did not match any expectation'

  httpsListen: ({key_path, cert_path, port, name}, callback=(->)) ->

    # {key,cert}
    fs.readFile key_path, (e, key) =>
      return callback e if e
      fs.readFile cert_path, (e, cert) =>
        return callback e if e

        server = https.createServer {key, cert}, ((req, res) => @handleRequest req, res)
        server.listen port, () =>
          # TODO handle error from .listen
          msg = "Listening on #{port}..."
          if name
            msg = "[#{name}] #{msg}"
          console.log msg
          callback null


class HTTPLogger
  constructor: () ->
    

  respond: (req, res, code, headers, body) ->
    res.writeHead code, headers
    res.end body

  requestText: (req, callback) ->
    arr = []
    req.on 'data', (data) =>
      arr.push data.toString 'utf-8'
    req.on 'end', () =>
      callback arr.join ''


module.exports = {MockingServer}
