define [
  'backbone'
  'cs!collections/media-types'
  'cs!collections/content'
  'cs!mixins/loadable'
  'cs!gh-book/xhtml-file'
  'cs!gh-book/toc-node'
  'cs!gh-book/toc-pointer-node'
  'cs!gh-book/utils'
], (Backbone, mediaTypes, allContent, loadable, XhtmlFile, TocNode, TocPointerNode, Utils) ->

  class PackageFile extends TocNode
    serializer = new XMLSerializer()

    mediaType: 'application/oebps-package+xml'
    accept: [XhtmlFile::mediaType, TocNode::mediaType]

    branch: true # This element will show up in the sidebar listing

    initialize: () ->
      super {root:@}

      # Contains all entries in the OPF file (including images)
      @manifest = new Backbone.Collection()
      # Contains all items in the ToC (including internal nodes like "Chapter 3")
      @tocNodes = new Backbone.Collection()
      @tocNodes.add @

      # Use the `parse:true` option instead of `loading:true` because
      # Backbone sets this option when a model is being parsed.
      # This way we can ignore firing events when Backbone is parsing as well as
      # when we are internally updating models.
      setNavModel = (options) =>
        if not options.doNotReparse
          options.doNotReparse = true
          @navModel.set 'body', @_serializeNavModel(), options

      @tocNodes.on 'tree:add',    (model, collection, options) => @tocNodes.add model, options
      @tocNodes.on 'tree:remove', (model, collection, options) => @tocNodes.remove model, options

      @getChildren().on 'tree:change add remove', (model, collection, options) =>
        setNavModel(options)
      @getChildren().on 'change reset', (collection, options) =>
        # HACK: `?` is because `inherits/container.add` calls `trigger('change')`
        setNavModel(options)

      @manifest.on 'add', (model, collection, options) =>
        $manifest = @$xml.find('manifest')

        # Check if the item is not already in the manifest
        return if $manifest.find("item[href='#{model.id}']")[0]

        # Create a new `<item>` in the manifest
        item = @$xml[0].createElementNS('http://www.idpf.org/2007/opf', 'item')
        $item = $(item)
        $item.attr
          href:         model.id
          id:           model.id # TODO: escape the slashes so it is a valid id
          'media-type': model.mediaType

        $manifest.append($item)
        # TODO: Depending on the type add it to the spine for EPUB2

        @_markDirty(options, true) # true == force because hasChanged == false


    _loadComplex: (fetchPromise) ->
      fetchPromise
      .then () =>
        # Clear that anything on the model has changed
        @changed = {}
        return @navModel.load()
      .then () =>
        @_parseNavModel()
        @listenTo @navModel, 'change:body', (model, value, options) =>
          @_parseNavModel() if not options.doNotReparse


    _parseNavModel: () ->
      $body = $(@navModel.get 'body')
      $body = $('<div></div>').append $body


      # Generate a tree of the ToC
      recBuildTree = (collection, $rootOl, contextPath) =>
        $rootOl.children('li').each (i, li) =>
          $li = $(li)

          # Remember attributes (like `class` and `data-`)
          attributes = Utils.elementAttributes $li

          # If the node contains a `<span>` then it is a container node
          # If the node contains a `<a>` then we currently only support them as leaves
          $a = $li.children('a')
          $span = $li.children('span')
          $ol = $li.children('ol')
          if $a[0]
            # Look up the href and add the piece of content
            title = $a.text()
            href = $a.attr('href')

            path = Utils.resolvePath(contextPath, href)
            contentModel = allContent.get path

            # Set all the titles of models in the workspace based on the nav tree
            # XhtmlModel titles are not saved anyway.
            contentModel.set 'title', title, {parse:true} if not contentModel.get('title')

            model = @newNode {title: title, htmlAttributes: attributes, model: contentModel}

            collection.add model, {doNotReparse:true}

          else if $span[0]
            model = new TocNode {title: $span.text(), htmlAttributes: attributes, root: @}

            # Recurse and then add the node. that way we reduce the number of notifications
            recBuildTree(model.getChildren(), $ol, contextPath) if $ol[0]
            collection.add model, {doNotReparse:true}

          else throw 'ERROR: Invalid Navigation Tree Structure'

          # Add the model to the tocNodes so we can listen to changes and update the ToC HTML
          @tocNodes.add model, {doNotReparse:true}


      $root = $body.find('nav > ol')
      @tocNodes.reset [@], {doNotReparse:true}
      @getChildren().reset([], {doNotReparse:true})
      recBuildTree(@getChildren(), $root, @navModel.id)


    _serializeNavModel: () ->
      $body = $(@navModel.get 'body')
      $wrapper = $('<div></div>').append $body
      $nav = $wrapper.find 'nav'
      $nav.empty()

      $navOl = $('<ol></ol>')

      recBuildList = ($rootOl, model) =>
        $li = $('<li></li>')
        $rootOl.append $li

        switch model.mediaType
          when XhtmlFile::mediaType
            path = Utils.relativePath(@navModel.id, model.id)
            $node = $('<a></a>')
            .attr('href', path)
          else
            $node = $('<span></span>')
            $li.attr(model.htmlAttributes or {})

        title = model.getTitle?() or model.get 'title'
        $node.html(title)
        $li.append $node

        if model.getChildren?().first()
          $ol = $('<ol></ol>')
          # recursively add children
          model.getChildren().forEach (child) => recBuildList($ol, child)
          $li.append $ol

      @getChildren().forEach (child) => recBuildList($navOl, child)
      $nav.append($navOl)
      $wrapper[0].innerHTML

    parse: (json) ->
      # Github.read returns a JSON with `{sha: "12345", content: "<rootfiles>...</rootfiles>"}
      # Save the commit sha so we can compare when a remote update occurs
      @commitSha = json.sha

      xmlStr = json.content

      # If the parse is a result of a write then update the sha.
      # The parse is a result of a GitHub.write if there is no `.content`
      return {} if not json.content

      @$xml = $($.parseXML xmlStr)

      # If we were unable to parse the XML then trigger an error
      return model.trigger 'error', 'INVALID_OPF' if not @$xml[0]

      # For the structure of the TOC file see `OPF_TEMPLATE`
      bookId = @$xml.find("##{@$xml.get 'unique-identifier'}").text()

      title = @$xml.find('title').text()

      # The manifest contains all the items in the spine
      # but the spine element says which order they are in

      @$xml.find('package > manifest > item').each (i, item) =>
        $item = $(item)

        # Add it to the set of all content and construct the correct model based on the mimetype
        mediaType = $item.attr 'media-type'
        path = $item.attr 'href'
        model = allContent.model
          # Set the path to the file to be relative to the OPF file
          id: Utils.resolvePath(@id, path)
          mediaType: mediaType
          properties: $item.attr 'properties'

        # Add it to the manifest and then do a batch add to `allContent`
        # at the end so the views do not re-sort on every add.
        @manifest.add model, {loading:true}

        # If we stumbled upon the special navigation document
        # then remember it.
        if 'nav' == $item.attr('properties')
          @navModel = model

      # Add all the models in one batch so views do not re-sort on every add.
      allContent.add @manifest.models, {loading:true}

      # Ignore the spine because it is defined by the navTree in EPUB3.
      # **TODO:** Fall back on `toc.ncx` and then the `spine` to create a navTree if one does not exist
      return {title: title, bookId: bookId}

    serialize: () -> serializer.serializeToString(@$xml[0])

    newNode: (options) ->
      model = options.model
      node = @tocNodes.get model.id
      if !node
        node = new TocPointerNode {root:@, model:model}
        #@tocNodes.add node
      return node

    # Defined in `mixins/tree`
    addChild: (model, at) ->
      # Clone if moving between two books
      # If `model` is a pointer (probably) then
      #
      # 1. Clone the underlying Content model (XHTMLFile)
      # 2. Create a new PointerNode
      # 3. Set the title of the new PointerNode to be "Copy of #{title}"

      root = @getRoot() or @
      modelRoot = model.getRoot?() # Case of dropping a book onto a folder... `or model`

      if root and modelRoot and root != modelRoot
        # If it is a pointer then dereference it
        title = model.get('title')
        realModel = model.dereferencePointer?() or model

        # To clone the content, load it first
        realModel.load()
        .fail(() => alert "ERROR: Problem loading #{realModel.id}. Try again later or refresh.")
        .done () =>
          json = realModel.toJSON()
          delete json.id

          clone = allContent.model(json)
          allContent.add(clone)

          newTitle = "Copy of #{title}"
          pointerNode = @newNode {title:newTitle, model:clone}
          pointerNode.set('title', newTitle)

          super(pointerNode, at)

      else
        super(model, at)

    # Do not change the contentView when the book opens
    contentView: null

    # Change the sidebar view when editing this
    sidebarView: (callback) ->
      require ['cs!views/workspace/sidebar/toc'], (View) =>
        view = new View
          collection: @getChildren()
          model: @
        callback(view)


  # Mix in the loadable
  PackageFile = PackageFile.extend loadable
