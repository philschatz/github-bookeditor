define ['cs!./new-book', 'cs!./new-module'], (newBook, newModule) ->
  module = newModule {title: 'Module in a Simple Book', body: '<p>Nothing</p>'}
  return {
    content: [
      module
      newBook
        title: 'Simple Book'
        body: """
          <nav>
            <ol>
              <li>
                <a href='#{module.id}' class='autogenerated-text'>[THIS TITLE SHOULD NOT BE VISIBLE]</a>
              </li>
            </ol>
          </nav>
        """
    ]
  }
