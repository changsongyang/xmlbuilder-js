{ assign } = require './Utility'

XMLDeclaration = require './XMLDeclaration'
XMLDocType = require './XMLDocType'

XMLCData = require './XMLCData'
XMLComment = require './XMLComment'
XMLElement = require './XMLElement'
XMLRaw = require './XMLRaw'
XMLText = require './XMLText'
XMLProcessingInstruction = require './XMLProcessingInstruction'
XMLDummy = require './XMLDummy'

XMLDTDAttList = require './XMLDTDAttList'
XMLDTDElement = require './XMLDTDElement'
XMLDTDEntity = require './XMLDTDEntity'
XMLDTDNotation = require './XMLDTDNotation'

WriterState = require './WriterState'

# Base class for XML writers
module.exports = class XMLWriterBase


  # Initializes a new instance of `XMLWriterBase`
  #
  # `options.pretty` pretty prints the result
  # `options.indent` indentation string
  # `options.newline` newline sequence
  # `options.offset` a fixed number of indentations to add to every line
  # `options.allowEmpty` do not self close empty element tags
  # 'options.dontPrettyTextNodes' if any text is present in node, don't indent or LF
  # `options.spaceBeforeSlash` add a space before the closing slash of empty elements
  constructor: (options) ->
    options or= {}
    @options = options

    # overwrite default properties
    for own key, value of options.writer or {}
      @["_" + key] = @[key]
      @[key] = value

  # Filters writer options and provides defaults
  #
  # `options` writer options
  filterOptions: (options) ->
    options or= {}
    options = assign {}, @options, options

    filteredOptions = { writer: @ }
    filteredOptions.pretty = options.pretty or false
    filteredOptions.allowEmpty = options.allowEmpty or false
    
    filteredOptions.indent = options.indent ? '  '
    filteredOptions.newline = options.newline ? '\n'
    filteredOptions.offset = options.offset ? 0
    filteredOptions.dontPrettyTextNodes = options.dontPrettyTextNodes ? options.dontprettytextnodes ? 0

    filteredOptions.spaceBeforeSlash = options.spaceBeforeSlash ? options.spacebeforeslash ? ''
    if filteredOptions.spaceBeforeSlash is true then filteredOptions.spaceBeforeSlash = ' '

    filteredOptions.suppressPrettyCount = 0

    filteredOptions.user = {}
    filteredOptions.state = WriterState.None

    return filteredOptions

  # Returns the indentation string for the current level
  #
  # `node` current node
  # `options` writer options
  # `level` current indentation level
  indent: (node, options, level) ->
    if not options.pretty or options.suppressPrettyCount
      return ''
    else if options.pretty
      indentLevel = (level or 0) + options.offset + 1
      if indentLevel > 0
        return new Array(indentLevel).join(options.indent)
        
    return ''

  # Returns the newline string
  #
  # `node` current node
  # `options` writer options
  # `level` current indentation level
  endline: (node, options, level) ->
    if not options.pretty or options.suppressPrettyCount
      return ''
    else
      return options.newline

  attribute: (att, options, level) ->
    @openNode(att, options, level)
    r = ' ' + att.name + '="' + att.value + '"'
    @closeNode(att, options, level)
    return r

  cdata: (node, options, level) ->
    @openNode(node, options, level)
    options.state = WriterState.OpenTag
    r = @indent(node, options, level) + '<![CDATA['
    options.state = WriterState.InsideTag
    r += node.text
    options.state = WriterState.CloseTag
    r += ']]>' + @endline(node, options, level)
    options.state = WriterState.None
    @closeNode(node, options, level)

    return r

  comment: (node, options, level) ->
    @openNode(node, options, level)
    options.state = WriterState.OpenTag
    r = @indent(node, options, level) + '<!-- '
    options.state = WriterState.InsideTag
    r += node.text
    options.state = WriterState.CloseTag
    r += ' -->' + @endline(node, options, level)
    options.state = WriterState.None
    @closeNode(node, options, level)

    return r

  declaration: (node, options, level) ->
    @openNode(node, options, level)
    options.state = WriterState.OpenTag
    r = @indent(node, options, level) + '<?xml'
    options.state = WriterState.InsideTag
    r += ' version="' + node.version + '"'
    r += ' encoding="' + node.encoding + '"' if node.encoding?
    r += ' standalone="' + node.standalone + '"' if node.standalone?
    options.state = WriterState.CloseTag
    r += options.spaceBeforeSlash + '?>'
    r += @endline(node, options, level)
    options.state = WriterState.None
    @closeNode(node, options, level)

    return r

  docType: (node, options, level) ->
    level or= 0

    @openNode(node, options, level)
    options.state = WriterState.OpenTag
    r = @indent(node, options, level)
    r += '<!DOCTYPE ' + node.root().name

    # external identifier
    if node.pubID and node.sysID
      r += ' PUBLIC "' + node.pubID + '" "' + node.sysID + '"'
    else if node.sysID
      r += ' SYSTEM "' + node.sysID + '"'

    # internal subset
    if node.children.length > 0
      r += ' ['
      r += @endline(node, options, level)
      options.state = WriterState.InsideTag
      for child in node.children
        r += switch
          when child instanceof XMLDTDAttList  then @dtdAttList  child, options, level + 1
          when child instanceof XMLDTDElement  then @dtdElement  child, options, level + 1
          when child instanceof XMLDTDEntity   then @dtdEntity   child, options, level + 1
          when child instanceof XMLDTDNotation then @dtdNotation child, options, level + 1
          when child instanceof XMLCData       then @cdata       child, options, level + 1
          when child instanceof XMLComment     then @comment     child, options, level + 1
          when child instanceof XMLProcessingInstruction then @processingInstruction child, options, level + 1
          else throw new Error "Unknown DTD node type: " + child.constructor.name
      options.state = WriterState.CloseTag
      r += ']'

    # close tag
    options.state = WriterState.CloseTag
    r += options.spaceBeforeSlash + '>'
    r += @endline(node, options, level)
    options.state = WriterState.None
    @closeNode(node, options, level)

    return r

  element: (node, options, level) ->
    level or= 0
    prettySuppressed = false

    r = ''

    # open tag
    @openNode(node, options, level)
    options.state = WriterState.OpenTag
    r += @indent(node, options, level) + '<' + node.name

    # attributes
    for own name, att of node.attributes
      r += @attribute att, level, options

    if node.children.length == 0 or node.children.every((e) -> e.value == '')
      # empty element
      if options.allowEmpty
        r += '>'
        options.state = WriterState.CloseTag
        r += '</' + node.name + '>' + @endline(node, options, level)
      else
        options.state = WriterState.CloseTag
        r += options.spaceBeforeSlash + '/>' + @endline(node, options, level)
    else if options.pretty and node.children.length == 1 and node.children[0].value?
      # do not indent text-only nodes
      r += '>'
      options.state = WriterState.InsideTag
      r += node.children[0].value
      options.state = WriterState.CloseTag
      r += '</' + node.name + '>' + @endline(node, options, level)
    else
      # if ANY are a text node, then suppress pretty now
      if options.dontPrettyTextNodes
        for child in node.children
          if child.value?
            options.suppressPrettyCount++
            prettySuppressed = true
            break

      # close the opening tag, after dealing with newline
      r += '>' + @endline(node, options, level)
      options.state = WriterState.InsideTag
      # inner tags
      for child in node.children
        r += switch
          when child instanceof XMLCData   then @cdata   child, options, level + 1
          when child instanceof XMLComment then @comment child, options, level + 1
          when child instanceof XMLElement then @element child, options, level + 1
          when child instanceof XMLRaw     then @raw     child, options, level + 1
          when child instanceof XMLText    then @text    child, options, level + 1
          when child instanceof XMLProcessingInstruction then @processingInstruction child, options, level + 1
          when child instanceof XMLDummy   then ''
          else throw new Error "Unknown XML node type: " + child.constructor.name

      # close tag
      options.state = WriterState.CloseTag
      r += @indent(node, options, level) + '</' + node.name + '>'

      if prettySuppressed
        options.suppressPrettyCount--

      r += @endline(node, options, level)
      options.state = WriterState.None

    @closeNode(node, options, level)

    return r

  processingInstruction: (node, options, level) ->
    @openNode(node, options, level)
    options.state = WriterState.OpenTag
    r = @indent(node, options, level) + '<?'
    options.state = WriterState.InsideTag
    r += node.target
    r += ' ' + node.value if node.value
    options.state = WriterState.CloseTag
    r += options.spaceBeforeSlash + '?>'
    r += @endline(node, options, level)
    options.state = WriterState.None
    @closeNode(node, options, level)

    return r

  raw: (node, options, level) ->
    @openNode(node, options, level)
    options.state = WriterState.OpenTag
    r = @indent(node, options, level)
    options.state = WriterState.InsideTag
    r += node.value
    options.state = WriterState.CloseTag
    r += @endline(node, options, level)
    options.state = WriterState.None
    @closeNode(node, options, level)

    return r

  text: (node, options, level) ->
    @openNode(node, options, level)
    options.state = WriterState.OpenTag
    r = @indent(node, options, level)
    options.state = WriterState.InsideTag
    r += node.value
    options.state = WriterState.CloseTag
    r += @endline(node, options, level)
    options.state = WriterState.None
    @closeNode(node, options, level)

    return r

  dtdAttList: (node, options, level) ->
    @openNode(node, options, level)
    options.state = WriterState.OpenTag
    r = @indent(node, options, level) + '<!ATTLIST'
    options.state = WriterState.InsideTag
    r += ' ' + node.elementName + ' ' + node.attributeName + ' ' + node.attributeType
    r += ' ' + node.defaultValueType if node.defaultValueType != '#DEFAULT'
    r += ' "' + node.defaultValue + '"' if node.defaultValue
    options.state = WriterState.CloseTag
    r += options.spaceBeforeSlash + '>' + @endline(node, options, level)
    options.state = WriterState.None
    @closeNode(node, options, level)

    return r

  dtdElement: (node, options, level) ->
    @openNode(node, options, level)
    options.state = WriterState.OpenTag
    r = @indent(node, options, level) + '<!ELEMENT'
    options.state = WriterState.InsideTag
    r += ' ' + node.name + ' ' + node.value
    options.state = WriterState.CloseTag
    r += options.spaceBeforeSlash + '>' + @endline(node, options, level)
    options.state = WriterState.None
    @closeNode(node, options, level)

    return r

  dtdEntity: (node, options, level) ->
    @openNode(node, options, level)
    options.state = WriterState.OpenTag
    r = @indent(node, options, level) + '<!ENTITY'
    options.state = WriterState.InsideTag
    r += ' %' if node.pe
    r += ' ' + node.name
    if node.value
      r += ' "' + node.value + '"'
    else
      if node.pubID and node.sysID
        r += ' PUBLIC "' + node.pubID + '" "' + node.sysID + '"'
      else if node.sysID
        r += ' SYSTEM "' + node.sysID + '"'
      r += ' NDATA ' + node.nData if node.nData
    options.state = WriterState.CloseTag
    r += options.spaceBeforeSlash + '>' + @endline(node, options, level)
    options.state = WriterState.None
    @closeNode(node, options, level)

    return r

  dtdNotation: (node, options, level) ->
    @openNode(node, options, level)
    options.state = WriterState.OpenTag
    r = @indent(node, options, level) + '<!NOTATION'
    options.state = WriterState.InsideTag
    r += ' ' + node.name
    if node.pubID and node.sysID
      r += ' PUBLIC "' + node.pubID + '" "' + node.sysID + '"'
    else if node.pubID
      r += ' PUBLIC "' + node.pubID + '"'
    else if node.sysID
      r += ' SYSTEM "' + node.sysID + '"'
    options.state = WriterState.CloseTag
    r += options.spaceBeforeSlash + '>' + @endline(node, options, level)
    options.state = WriterState.None
    @closeNode(node, options, level)

    return r

  openNode: (node, options, level) ->

  closeNode: (node, options, level) ->

