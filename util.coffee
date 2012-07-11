
clone = (x) ->
  JSON.parse JSON.stringify x


timeoutSet = (ms, f) ->
  setTimeout f, ms


dictionaries_equal = (d1, d2) ->
  d1 = clone d1
  for own k of d2
    return false if d1[k] != d2[k]
    delete d1[k]
  return false if _.keys(d1).length != 0
  true


pretty_json_stringify = (x) ->
  JSON.stringify x, null, '  '


module.exports = {clone, timeoutSet, dictionaries_equal, pretty_json_stringify}
