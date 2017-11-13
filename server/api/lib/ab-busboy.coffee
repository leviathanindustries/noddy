import Busboy from 'busboy'

# TODO could make this only apply to certain routes, and handle it directly

JsonRoutes.Middleware.use (req, res, next) ->
  if req.headers?['content-type']?.match(/^multipart\/form\-data/)
    busboy = new Busboy {headers: req.headers}
    req.files = []

    busboy.on 'file', (fieldname, file, filename, encoding, mimetype) ->
      uploadedFile = {
        filename,
        mimetype,
        encoding,
        fieldname,
        data: null
      }

      API.log msg: 'busboy have file...', uploadedFile, level: 'debug'
      buffers = []
      file.on 'data', (data) ->
        API.log msg: 'data length: ' + data.length, level: 'debug'
        buffers.push data
      file.on 'end', () ->
        console.log msg: 'End of busboy file', level: 'debug'
        uploadedFile.data = Buffer.concat buffers
        req.files.push uploadedFile

    busboy.on "field", (fieldname, value) -> req.body[fieldname] = value

    busboy.on 'finish', () -> next()

    req.pipe busboy
    return

  next()
