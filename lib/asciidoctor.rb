RUBY_ENGINE = 'unknown' unless defined? RUBY_ENGINE
RUBY_ENGINE_OPAL = (RUBY_ENGINE == 'opal')
RUBY_ENGINE_JRUBY = (RUBY_ENGINE == 'jruby')

require 'set'

if RUBY_ENGINE_OPAL
  require 'strscan'
  require 'asciidoctor/opal_ext/dir'
  require 'asciidoctor/opal_ext/error'
  require 'asciidoctor/opal_ext/file'
end

# ideally we should use require_relative instead of modifying the LOAD_PATH
$:.unshift(File.dirname __FILE__)

# Public: Methods for parsing Asciidoc input files and rendering documents
# using eRuby templates.
#
# Asciidoc documents comprise a header followed by zero or more sections.
# Sections are composed of blocks of content.  For example:
#
#   = Doc Title
#
#   == Section 1
#
#   This is a paragraph block in the first section.
#
#   == Section 2
#
#   This section has a paragraph block and an olist block.
#
#   . Item 1
#   . Item 2
#
# Examples:
#
# Use built-in templates:
#
#   lines = File.readlines("your_file.asc")
#   doc = Asciidoctor::Document.new(lines)
#   html = doc.render
#   File.open("your_file.html", "w+") do |file|
#     file.puts html
#   end
#
# Use custom (Tilt-supported) templates:
#
#   lines = File.readlines("your_file.asc")
#   doc = Asciidoctor::Document.new(lines, :template_dir => 'templates')
#   html = doc.render
#   File.open("your_file.html", "w+") do |file|
#     file.puts html
#   end
module Asciidoctor

  unless RUBY_ENGINE_OPAL
    # .chomp keeps Opal from trying to load the library
    ::Object.autoload :Base64,        'base64'.chomp
    ::Object.autoload :ERB,           'erb'.chomp
    ::Object.autoload :FileUtils,     'fileutils'.chomp
    ::Object.autoload :OpenURI,       'open-uri'.chomp
    #::Object.autoload :Set,           'set'.chomp
    ::Object.autoload :StringScanner, 'strscan'.chomp
  end

  module SafeMode

    # A safe mode level that disables any of the security features enforced
    # by Asciidoctor (Ruby is still subject to its own restrictions).
    UNSAFE = 0;

    # A safe mode level that closely parallels safe mode in AsciiDoc. This value
    # prevents access to files which reside outside of the parent directory of
    # the source file and disables any macro other than the include::[] macro.
    SAFE = 1;

    # A safe mode level that disallows the document from setting attributes
    # that would affect the rendering of the document, in addition to all the
    # security features of SafeMode::SAFE. For instance, this level disallows
    # changing the backend or the source-highlighter using an attribute defined
    # in the source document. This is the most fundamental level of security
    # for server-side deployments (hence the name).
    SERVER = 10;

    # A safe mode level that disallows the document from attempting to read
    # files from the file system and including the contents of them into the
    # document, in additional to all the security features of SafeMode::SERVER.
    # For instance, this level disallows use of the include::[] macro and the
    # embedding of binary content (data uri), stylesheets and JavaScripts
    # referenced by the document.(Asciidoctor and trusted extensions may still
    # be allowed to embed trusted content into the document).
    #
    # Since Asciidoctor is aiming for wide adoption, this level is the default
    # and is recommended for server-side deployments.
    SECURE = 20;

    # A planned safe mode level that disallows the use of passthrough macros and
    # prevents the document from setting any known attributes, in addition to all
    # the security features of SafeMode::SECURE.
    #
    # Please note that this level is not currently implemented (and therefore not
    # enforced)!
    #PARANOID = 100;

  end

  # Flags to control compliance with the behavior of AsciiDoc
  module Compliance
    # AsciiDoc terminates paragraphs adjacent to
    # block content (delimiter or block attribute list)
    # This option allows this behavior to be modified
    # TODO what about literal paragraph?
    # Compliance value: true
    @block_terminates_paragraph = true
    class << self
      attr_accessor :block_terminates_paragraph
    end

    # AsciiDoc does not treat paragraphs labeled with a verbatim style
    # (literal, listing, source, verse) as verbatim
    # This options allows this behavior to be modified
    # Compliance value: false
    @strict_verbatim_paragraphs = true
    class << self
      attr_accessor :strict_verbatim_paragraphs
    end

    # NOT CURRENTLY USED
    # AsciiDoc allows start and end delimiters around
    # a block to be different lengths
    # Enabling this option requires matching lengths
    # Compliance value: false
    #@congruent_block_delimiters = true
    #class << self
    #  attr_accessor :congruent_block_delimiters
    #end

    # AsciiDoc supports both single-line and underlined
    # section titles.
    # This option disables the underlined variant.
    # Compliance value: true
    @underline_style_section_titles = true
    class << self
      attr_accessor :underline_style_section_titles
    end

    # Asciidoctor will unwrap the content in a preamble
    # if the document has a title and no sections.
    # Compliance value: false
    @unwrap_standalone_preamble = true
    class << self
      attr_accessor :unwrap_standalone_preamble
    end

    # AsciiDoc drops lines that contain references to missing attributes.
    # This behavior is not intuitive to most writers
    # Compliance value: 'drop-line'
    @attribute_missing = 'skip'
    class << self
      attr_accessor :attribute_missing
    end

    # AsciiDoc drops lines that contain an attribute unassignemnt.
    # This behavior may need to be tuned depending on the circumstances.
    # Compliance value: 'drop-line'
    @attribute_undefined = 'drop-line'
    class << self
      attr_accessor :attribute_undefined
    end

    # Asciidoctor will recognize commonly-used Markdown syntax
    # to the degree it does not interfere with existing
    # AsciiDoc syntax and behavior.
    # Compliance value: false
    @markdown_syntax = true
    class << self
      attr_accessor :markdown_syntax
    end
  end

  # The absolute lib path of the Asciidoctor RubyGem
  LIB_PATH = ::File.expand_path(::File.dirname __FILE__)

  # The absolute root path of the Asciidoctor RubyGem
  ROOT_PATH = ::File.dirname LIB_PATH

  # The user's home directory, as best we can determine it
  USER_HOME = RUBY_VERSION >= '1.9' ? ::Dir.home : ENV['HOME']

  # Flag to indicate whether encoding of external strings needs to be forced to UTF-8
  # _All_ input data must be force encoded to UTF-8 if Encoding.default_external is *not* UTF-8
  # Address failures performing string operations that are reported as "invalid byte sequence in US-ASCII" 
  # Ruby 1.8 doesn't seem to experience this problem (perhaps because it isn't validating the encodings)
  FORCE_ENCODING = !RUBY_ENGINE_OPAL && RUBY_VERSION >= '1.9' && ::Encoding.default_external != ::Encoding::UTF_8

  # Flag to indicate that line length should be calculated using a unicode mode hint
  FORCE_UNICODE_LINE_LENGTH = RUBY_VERSION < '1.9'

  # The endline character to use when rendering output
  EOL = "\n"

  # The pattern to use for splitting lines
  LINE_SPLIT = /\n/

  # The default document type
  # Can influence markup generated by render templates
  DEFAULT_DOCTYPE = 'article'

  # The backend determines the format of the rendered output, default to html5
  DEFAULT_BACKEND = 'html5'

  DEFAULT_STYLESHEET_KEYS = ['', 'DEFAULT'].to_set

  DEFAULT_STYLESHEET_NAME = 'asciidoctor.css'

  # Pointers to the preferred version for a given backend.
  BACKEND_ALIASES = {
    'html'    => 'html5',
    'docbook' => 'docbook45'
  }

  # Default page widths for calculating absolute widths
  DEFAULT_PAGE_WIDTHS = {
    'docbook' => 425
  }

  # Default extensions for the respective base backends
  DEFAULT_EXTENSIONS = {
    'html' => '.html',
    'docbook' => '.xml',
    'asciidoc' => '.ad',
    'markdown' => '.md'
  }

  # Set of file extensions recognized as AsciiDoc documents (stored as a truth hash)
  ASCIIDOC_EXTENSIONS = {
    '.asciidoc' => true,
    '.adoc' => true,
    '.ad' => true,
    '.asc' => true,
    '.txt' => true
  }

  SECTION_LEVELS = {
    '=' => 0,
    '-' => 1,
    '~' => 2,
    '^' => 3,
    '+' => 4
  }

  ADMONITION_STYLES = ['NOTE', 'TIP', 'IMPORTANT', 'WARNING', 'CAUTION'].to_set

  PARAGRAPH_STYLES = ['comment', 'example', 'literal', 'listing', 'normal', 'pass', 'quote', 'sidebar', 'source', 'verse', 'abstract', 'partintro'].to_set

  VERBATIM_STYLES = ['literal', 'listing', 'source', 'verse'].to_set

  DELIMITED_BLOCKS = {
    '--'   => [:open, ['comment', 'example', 'literal', 'listing', 'pass', 'quote', 'sidebar', 'source', 'verse', 'admonition', 'abstract', 'partintro'].to_set],
    '----' => [:listing, ['literal', 'source'].to_set],
    '....' => [:literal, ['listing', 'source'].to_set],
    '====' => [:example, ['admonition'].to_set],
    '****' => [:sidebar, ::Set.new],
    '____' => [:quote, ['verse'].to_set],
    '""'   => [:quote, ['verse'].to_set],
    '++++' => [:pass, ['math', 'latexmath', 'asciimath'].to_set],
    '|===' => [:table, ::Set.new],
    ',===' => [:table, ::Set.new],
    ':===' => [:table, ::Set.new],
    '!===' => [:table, ::Set.new],
    '////' => [:comment, ::Set.new],
    '```'  => [:fenced_code, ::Set.new],
    '~~~'  => [:fenced_code, ::Set.new]
  }

  DELIMITED_BLOCK_LEADERS = DELIMITED_BLOCKS.keys.map {|key| key[0..1] }.to_set

  BREAK_LINES = {
    '\'' => :ruler,
    '-'  => :ruler,
    '*'  => :ruler,
    '_'  => :ruler,
    '<'  => :page_break
  }

  #LIST_CONTEXTS = [:ulist, :olist, :dlist, :colist]

  NESTABLE_LIST_CONTEXTS = [:ulist, :olist, :dlist]

  # TODO validate use of explicit style name above ordered list (this list is for selecting an implicit style)
  ORDERED_LIST_STYLES = [:arabic, :loweralpha, :lowerroman, :upperalpha, :upperroman] #, :lowergreek]

  ORDERED_LIST_MARKER_PATTERNS = {
    :arabic => /\d+[.>]/,
    :loweralpha => /[a-z]\./,
    :lowerroman => /[ivx]+\)/,
    :upperalpha => /[A-Z]\./,
    :upperroman => /[IVX]+\)/
    #:lowergreek => /[a-z]\]/
  }

  ORDERED_LIST_KEYWORDS = {
    'loweralpha' => 'a',
    'lowerroman' => 'i',
    'upperalpha' => 'A',
    'upperroman' => 'I'
    #'lowergreek' => 'a'
    #'arabic'     => '1'
    #'decimal'    => '1'
  }

  LIST_CONTINUATION = '+'

  LINE_BREAK = ' +'

  LINE_FEED_ENTITY = '&#10;' # or &#x0A;

  BLOCK_MATH_DELIMITERS = {
    :asciimath => ['\\$', '\\$'],
    :latexmath => ['\\[', '\\]'],
  }

  INLINE_MATH_DELIMITERS = {
    :asciimath => ['\\$', '\\$'],
    :latexmath => ['\\(', '\\)'],
  }

  # attributes which be changed within the content of the document (but not
  # header) because it has semantic meaning; ex. numbered
  FLEXIBLE_ATTRIBUTES = %w(numbered)

  # Regular expression character classes (dependent on regexp engine)
  if RUBY_ENGINE_OPAL
    CC_ALPHA = 'a-zA-Z'
    CC_ALNUM = 'a-zA-Z0-9'
    CC_BLANK = '[ \t]'
    CC_GRAPH = '[\x21-\x7E]' # non-blank character
    CC_EOL   = '(?=\n|$)'
  else
    CC_ALPHA = '[:alpha:]'
    CC_ALNUM = '[:alnum:]'
    CC_BLANK = '[[:blank:]]'
    CC_GRAPH = '[[:graph:]]' # non-blank character
    CC_EOL   = '$'
  end

  # NOTE allows for empty space in line as it could be left by the template engine
  BLANK_LINE_PATTERN = /^#{CC_BLANK}*\n/

  # Delimiters and matchers for the passthrough placeholder
  # See http://www.aivosto.com/vbtips/control-characters.html#listabout for characters to use
  PASS_PLACEHOLDER = {
    # SPA, start of guarded protected area
    :start  => RUBY_ENGINE_OPAL ? 150.chr : "\u0096",
    # EPA, end of guarded protected area
    :end    => RUBY_ENGINE_OPAL ? 151.chr : "\u0097",
    # match placeholder record
    :match  => /\u0096(\d+)\u0097/,
    # fix placeholder record after syntax highlighting
    :match_syn => /<span[^>]*>\u0096<\/span>[^\d]*(\d+)[^\d]*<span[^>]*>\u0097<\/span>/
  }

  # The following pattern, which appears frequently, captures the contents between square brackets,
  # ignoring escaped closing brackets (closing brackets prefixed with a backslash '\' character)
  #
  # Pattern:
  # (?:\[((?:\\\]|[^\]])*?)\])
  # Matches:
  # [enclosed text here] or [enclosed [text\] here]
  REGEXP = {
    #:strip_line_wise => /\A(?:\s*\n)?(.*?)\s*\z/m,

    # NOTE: this is a inline admonition note
    :admonition_inline => /^(#{ADMONITION_STYLES.to_a * '|'}):#{CC_BLANK}/,

    # [[idname]]
    # [[idname,Reference Text]]
    :anchor           => /^\[\[(?:|([#{CC_ALPHA}:_][\w:.-]*)(?:,#{CC_BLANK}*(\S.*))?)\]\]$/,

    # Section Title [[idname]]
    # Section Title [[idname,Reference Text]]
    :anchor_embedded  => /^(.*?)#{CC_BLANK}+(\\)?\[\[([#{CC_ALPHA}:_][\w:.-]*)(?:,#{CC_BLANK}*(\S.*?))?\]\]$/,

    # Anywhere inline:
    # [[idname]]
    # [[idname,Reference Text]]
    # anchor:idname[]
    # anchor:idname[Reference Text]
    :anchor_macro     => /\\?(?:\[\[([#{CC_ALPHA}:_][\w:.-]*)(?:,#{CC_BLANK}*(\S.*?))?\]\]|anchor:(\S+)\[(.*?[^\\])?\])/,

    # matches any unbounded block delimiter:
    #   listing, literal, example, sidebar, quote, passthrough, table, fenced code
    # does not include open block or air quotes
    # TIP position the most common blocks towards the front of the pattern
    :any_blk          => %r{^(?:(?:-|\.|=|\*|_|\+|/){4,}|[\|,;!]={3,}|(?:`|~){3,}.*)$},

    # detect a list item of any sort
    :any_list         => /^(?:<?\d+>#{CC_BLANK}+#{CC_GRAPH}|#{CC_BLANK}*(?:-|(?:\*|\.){1,5}|\d+\.|[a-zA-Z]\.|[IVXivx]+\))#{CC_BLANK}+#{CC_GRAPH}|#{CC_BLANK}*.*?(?::{2,4}|;;)(?:#{CC_BLANK}+#{CC_GRAPH}|$))/,

    # :foo: bar
    # :Author: Dan
    # :numbered!:
    # :long-entry: Attribute value lines ending in ' +'
    #              are joined together as a single value,
    #              collapsing the line breaks and indentation to
    #              a single space.
    :attr_entry       => /^:(!?\w.*?):(?:#{CC_BLANK}+(.*))?$/,

    # An attribute list above a block element
    #
    # Can be strictly positional:
    # [quote, Adam Smith, Wealth of Nations]
    # Or can have name/value pairs
    # [NOTE, caption="Good to know"]
    # Can be defined by an attribute
    # [{lead}]
    :blk_attr_list    => /^\[(|#{CC_BLANK}*[\w\{,.#"'%].*)\]$/,

    # block attribute list or block anchor (bulk query)
    :attr_line        => /^\[(|#{CC_BLANK}*[\w\{,.#"'%].*|\[(?:|[#{CC_ALPHA}:_][\w:.-]*(?:,#{CC_BLANK}*\S.*)?)\])\]$/,

    # attribute reference
    # {foo}
    # {counter:pcount:1}
    # {set:foo:bar}
    # {set:name!}
    :attr_ref         => /(\\)?\{((set|counter2?):.+?|\w+(?:[\-]\w+)*)(\\)?\}/,

    # The author info line the appears immediately following the document title
    # John Doe <john@anonymous.com>
    :author_info      => /^(\w[\w\-'.]*)(?: +(\w[\w\-'.]*))?(?: +(\w[\w\-'.]*))?(?: +<([^>]+)>)?$/,

    # [[[Foo]]] (anywhere inline)
    :biblio_macro     => /\\?\[\[\[([\w:][\w:.-]*?)\]\]\]/,

    # callout reference inside literal text
    # <1> (optionally prefixed by //, # or ;; line comment chars)
    # <1> <2> (multiple callouts on one line)
    # <!--1--> (for XML-based languages)
    # special characters are already be replaced at this point during render
    :callout_render     => /(?:(?:\/\/|#|;;) ?)?(\\)?&lt;!?(--|)(\d+)\2&gt;(?=(?: ?\\?&lt;!?\2\d+\2&gt;)*#{CC_EOL})/,
    # ...but not while scanning
    :callout_quick_scan => /\\?<!?(--|)(\d+)\1>(?=(?: ?\\?<!?\1\d+\1>)*#{CC_EOL})/,
    :callout_scan       => /(?:(?:\/\/|#|;;) ?)?(\\)?<!?(--|)(\d+)\2>(?=(?: ?\\?<!?\2\d+\2>)*#{CC_EOL})/,

    # <1> Foo
    :colist           => /^<?(\d+)>#{CC_BLANK}+(.*)/,

    # ////
    # comment block
    # ////
    :comment_blk      => %r{^/{4,}$},

    # // (and then whatever)
    :comment          => %r{^//(?:[^/]|$)},

    # one,two;three;four
    :ssv_or_csv_delim => /,|;/,

    # one two	three
    :space_delim      => /([^\\])#{CC_BLANK}+/,

    # Ctrl + Alt+T
    # Ctrl,T
    :kbd_delim        => /(?:\+|,)(?=#{CC_BLANK}*[^\1])/,

    # one\ two\	three
    :escaped_space    => /\\(#{CC_BLANK})/,

    # 29
    :digits           => /^\d+$/,

    # foo::  ||  foo::: || foo:::: || foo;;
    # Should be followed by a definition, on the same line...
    # foo:: That which precedes 'bar' (see also, <<bar>>)
    # ...or on a separate line
    # foo::
    #   That which precedes 'bar' (see also, <<bar>>)
    # The term may be an attribute reference
    # {term_foo}:: {def_foo}
    # NOTE negative match for comment line is intentional since that isn't handled when looking for next list item
    # QUESTION should we check for line comment in regex or when scanning the lines?
    :dlist            => /^(?!\/\/)#{CC_BLANK}*(.*?)(:{2,4}|;;)(?:#{CC_BLANK}+(.*))?$/,
    :dlist_siblings   => {
                           # (?:.*?[^:])? - a non-capturing group which grabs longest sequence of characters that doesn't end w/ colon
                           '::' => /^(?!\/\/)#{CC_BLANK}*((?:.*[^:])?)(::)(?:#{CC_BLANK}+(.*))?$/,
                           ':::' => /^(?!\/\/)#{CC_BLANK}*((?:.*[^:])?)(:::)(?:#{CC_BLANK}+(.*))?$/,
                           '::::' => /^(?!\/\/)#{CC_BLANK}*((?:.*[^:])?)(::::)(?:#{CC_BLANK}+(.*))?$/,
                           ';;' => /^(?!\/\/)#{CC_BLANK}*(.*)(;;)(?:#{CC_BLANK}+(.*))?$/
                         },

    :illegal_sectid_chars => /&(?:[a-zA-Z]{2,}|#\d{2,4}|#x[a-fA-F0-9]{2,4});|\W+?/,

    # footnote:[text]
    # footnoteref:[id,text]
    # footnoteref:[id]
    :footnote_macro   => /\\?(footnote(?:ref)?):\[(.*?[^\\])\]/m,

    # gist::123456[]
    :generic_blk_macro => /^(\w[\w\-]*)::(\S+?)\[((?:\\\]|[^\]])*?)\]$/,

    # kbd:[F3]
    # kbd:[Ctrl+Shift+T]
    # kbd:[Ctrl+\]]
    # kbd:[Ctrl,T]
    # btn:[Save]
    :kbd_btn_macro    => /\\?(?:kbd|btn):\[((?:\\\]|[^\]])+?)\]/,

    # menu:File[New...]
    # menu:View[Page Style > No Style]
    # menu:View[Page Style, No Style]
    :menu_macro       => /\\?menu:(\w|\w.*?\S)\[#{CC_BLANK}*(.+?)?\]/,

    # "File > New..."
    :menu_inline_macro  => /\\?"(\w[^"]*?#{CC_BLANK}*&gt;#{CC_BLANK}*[^" \t][^"]*)"/,

    # image::filename.png[Caption]
    # video::http://youtube.com/12345[Cats vs Dogs]
    :media_blk_macro  => /^(image|video|audio)::(\S+?)\[((?:\\\]|[^\]])*?)\]$/,

    # image:filename.png[Alt Text]
    # image:http://example.com/images/filename.png[Alt Text]
    # image:filename.png[More [Alt\] Text] (alt text becomes "More [Alt] Text")
    # icon:github[large]
    :image_macro      => /\\?(?:image|icon):([^:\[][^\[]*)\[((?:\\\]|[^\]])*?)\]/,

    # indexterm:[Tigers,Big cats]
    # (((Tigers,Big cats)))
    # indexterm2:[Tigers]
    # ((Tigers))
    :indexterm_macro   => /\\?(?:(indexterm2?):\[(.*?[^\\])\]|\(\((.+?)\)\)(?!\)))/m,

    # whitespace at the beginning of the line
    :leading_blanks   => /^(#{CC_BLANK}*)/,

    # leading parent directory references in path
    :leading_parent_dirs => /^(?:\.\.\/)*/,

    # +   From the Asciidoc User Guide: "A plus character preceded by at
    #     least one space character at the end of a non-blank line forces
    #     a line break. It generates a line break (br) tag for HTML outputs.
    #
    # +      (would not match because there's no space before +)
    #  +     (would match and capture '')
    # Foo +  (would and capture 'Foo')
    :line_break       => /^(.*)#{CC_BLANK}\+#{CC_EOL}/,

    # inline link and some inline link macro
    # FIXME revisit!
    :link_inline      => %r{(^|link:|\s|>|&lt;|[\(\)\[\]])(\\?(?:https?|ftp|irc)://[^\s\[\]<]*[^\s.,\[\]<])(?:\[((?:\\\]|[^\]])*?)\])?},

    # inline link macro
    # link:path[label]
    :link_macro       => /\\?(?:link|mailto):([^\s\[]+)(?:\[((?:\\\]|[^\]])*?)\])/,

    # inline email address
    # doc.writer@asciidoc.org
    :email_inline     => /[\\>:]?\w[\w.%+-]*@[#{CC_ALNUM}][#{CC_ALNUM}.-]*\.[#{CC_ALPHA}]{2,4}\b/,

    # <TAB>Foo  or one-or-more-spaces-or-tabs then whatever
    :lit_par          => /^(#{CC_BLANK}+.*)$/,

    # . Foo (up to 5 consecutive dots)
    # 1. Foo (arabic, default)
    # a. Foo (loweralpha)
    # A. Foo (upperalpha)
    # i. Foo (lowerroman)
    # I. Foo (upperroman)
    # NOTE leading space match is not always necessary, but is used for list reader
    :olist            => /^#{CC_BLANK}*(\.{1,5}|\d+\.|[a-zA-Z]\.|[IVXivx]+\))#{CC_BLANK}+(.*)$/,

    # ''' (ruler)
    # <<< (pagebreak)
    :break_line        => /^('|<){3,}$/,

    # ''' or ' ' ' (ruler)
    # --- or - - - (ruler)
    # *** or * * * (ruler)
    # <<< (pagebreak)
    :break_line_plus   => /^(?:'|<){3,}$|^ {0,3}([-\*_])( *)\1\2\1$/,

    # inline passthrough macros
    # +++text+++
    # $$text$$
    # pass:quotes[text]
    :pass_macro       => /\\?(?:(\+{3}|\${2})(.*?)\1|pass:([a-z,]*)\[(.*?[^\\])\])/m,

    # math:[x != 0]
    # asciimath:[x != 0]
    # latexmath:[\sqrt{4} = 2]
    :inline_math_macro => /\\?((?:latex|ascii)?math):([a-z,]*)\[(.*?[^\\])\]/m,

    # passthrough macro allowed in value of attribute assignment
    # pass:[text]
    :pass_macro_basic => /^pass:([a-z,]*)\[(.*)\]$/,

    # inline literal passthrough macro
    # `text`
    :pass_lit         => /(^|[^`\w])(?:\[([^\]]+?)\])?(\\?`([^`\s]|[^`\s].*?\S)`)(?![`\w])/m,

    # The document revision info line the appears immediately following the
    # document title author info line, if present
    # v1.0, 2013-01-01: Ring in the new year release
    :revision_info    => /^(?:\D*(.*?),)?(?:\s*(?!:)(.*?))(?:\s*(?!^):\s*(.*))?$/,

    # \' within a word
    :single_quote_esc => /(\w)\\'(\w)/,
    # an alternative if our backend generated single-quoted html/xml attributes
    #:single_quote_esc => /(\w|=)\\'(\w)/,

    # used for sanitizing attribute names
    :illegal_attr_name_chars => /[^\w\-]/,

    # 1*h,2*,^3e
    :table_colspec    => /^(?:(\d+)\*)?([<^>](?:\.[<^>]?)?|(?:[<^>]?\.)?[<^>])?(\d+%?)?([a-z])?$/,

    # 2.3+<.>m
    # TODO might want to use step-wise scan rather than this mega-regexp
    :table_cellspec => {
      :start => /^#{CC_BLANK}*(?:(\d+(?:\.\d*)?|(?:\d*\.)?\d+)([*+]))?([<^>](?:\.[<^>]?)?|(?:[<^>]?\.)?[<^>])?([a-z])?\|/,
      :end => /#{CC_BLANK}+(?:(\d+(?:\.\d*)?|(?:\d*\.)?\d+)([*+]))?([<^>](?:\.[<^>]?)?|(?:[<^>]?\.)?[<^>])?([a-z])?$/
    },

    # docbook45
    # html5
    :trailing_digit   => /\d+$/,

    # .Foo   but not  . Foo or ..Foo
    :blk_title        => /^\.([^\s.].*)$/,

    # matches double quoted text, capturing quote char and text (single-line)
    :dbl_quoted       => /^("|)(.*)\1$/,

    # matches double quoted text, capturing quote char and text (multi-line)
    :m_dbl_quoted     => /^("|)(.*)\1$/m,

    # == Foo
    # ^ yields a level 2 title
    #
    # == Foo ==
    # ^ also yields a level 2 title
    #
    # both equivalent to this two-line version:
    # Foo
    # ~~~
    #
    # match[1] is the delimiter, whose length determines the level
    # match[2] is the title itself
    # match[3] is an inline anchor, which becomes the section id
    :section_title     => /^((?:=|#){1,6})#{CC_BLANK}+(\S.*?)(?:#{CC_BLANK}+\1)?$/,

    # restricted section name for two-line section title
    # does not begin with a dot and has at least one alphanumeric character
    :section_name      => /^((?=.*\w+.*)[^.].*?)$/,

    # ======  || ------ || ~~~~~~ || ^^^^^^ || ++++++
    # TODO build from SECTION_LEVELS keys
    :section_underline => /^(?:=|-|~|\^|\+)+$/,

    # toc::[]
    # toc::[levels=2]
    :toc              => /^toc::\[(.*?)\]$/,

    # * Foo (up to 5 consecutive asterisks)
    # - Foo
    # NOTE leading space match is not always necessary, but is used for list reader
    :ulist            => /^#{CC_BLANK}*(-|\*{1,5})#{CC_BLANK}+(.*)$/,

    # inline xref macro
    # <<id,reftext>> (special characters have already been escaped, hence the entity references)
    # xref:id[reftext]
    :xref_macro       => /\\?(?:&lt;&lt;([\w":].*?)&gt;&gt;|xref:([\w":].*?)\[(.*?)\])/m,

    # ifdef::basebackend-html[]
    # ifndef::theme[]
    # ifeval::["{asciidoctor-version}" >= "0.1.0"]
    # ifdef::asciidoctor[Asciidoctor!]
    # endif::theme[]
    # endif::basebackend-html[]
    # endif::[]
    :ifdef_macro      => /^[\\]?(ifdef|ifndef|ifeval|endif)::(\S*?(?:([,\+])\S+?)?)\[(.+)?\]$/,

    # "{asciidoctor-version}" >= "0.1.0"
    :eval_expr        => /^(\S.*?)#{CC_BLANK}*(==|!=|<=|>=|<|>)#{CC_BLANK}*(\S.*)$/,
    # ...or if we want to be more strict up front about what's on each side
    #:eval_expr        => /^(true|false|("|'|)\{\w+(?:\-\w+)*\}\2|("|')[^\3]*\3|\-?\d+(?:\.\d+)*)#{CC_BLANK}*(==|!=|<=|>=|<|>)#{CC_BLANK}*(true|false|("|'|)\{\w+(?:\-\w+)*\}\6|("|')[^\7]*\7|\-?\d+(?:\.\d+)*)$/,

    # include::chapter1.ad[]
    # include::example.txt[lines=1;2;5..10]
    :include_macro    => /^\\?include::([^\[]+)\[(.*?)\]$/,

    # http://domain
    # https://domain
    # data:info
    :uri_sniff        => %r{^[#{CC_ALPHA}][#{CC_ALNUM}.+-]*:/{0,2}},

    :uri_encode_chars => /[^\w\-.!~*';:@=+$,()\[\]]/,

    :mantitle_manvolnum => /^(.*)\((.*)\)$/,

    :manname_manpurpose => /^(.*?)#{CC_BLANK}+-#{CC_BLANK}+(.*)$/
  }

  INTRINSICS = ::Hash.new{|h,k| STDERR.puts "Missing intrinsic: #{k.inspect}"; "{#{k}}"}.merge(
    {
    'startsb'    => '[',
    'endsb'      => ']',
    'vbar'       => '|',
    'caret'      => '^',
    'asterisk'   => '*',
    'tilde'      => '~',
    'plus'       => '&#43;',
    'apostrophe' => '\'',
    'backslash'  => '\\',
    'backtick'   => '`',
    'empty'      => '',
    'sp'         => ' ',
    'space'      => ' ',
    'two-colons' => '::',
    'two-semicolons' => ';;',
    'nbsp'       => '&#160;',
    'deg'        => '&#176;',
    'zwsp'       => '&#8203;',
    'quot'       => '&#34;',
    'apos'       => '&#39;',
    'lsquo'      => '&#8216;',
    'rsquo'      => '&#8217;',
    'ldquo'      => '&#8220;',
    'rdquo'      => '&#8221;',
    'wj'         => '&#8288;',
    'brvbar'     => '&#166;',
    'amp'        => '&',
    'lt'         => '<',
    'gt'         => '>'
    }
  )

  SPECIAL_CHARS = {
    '<' => '&lt;',
    '>' => '&gt;',
    '&' => '&amp;'
  }

  SPECIAL_CHARS_PATTERN = /[#{SPECIAL_CHARS.keys.join}]/
  #SPECIAL_CHARS_PATTERN = /(?:<|>|&(?![a-zA-Z]{2,};|#\d{2,4};|#x[a-fA-F0-9]{2,4};))/

  # unconstrained quotes:: can appear anywhere
  # constrained quotes:: must be bordered by non-word characters
  # NOTE these substitutions are processed in the order they appear here and
  # the order in which they are replaced is important
  QUOTE_SUBS = [

    # **strong**
    [:strong, :unconstrained, /\\?(?:\[([^\]]+?)\])?\*\*(.+?)\*\*/m],

    # *strong*
    [:strong, :constrained, /(^|[^\w;:}])(?:\[([^\]]+?)\])?\*(\S|\S.*?\S)\*(?=\W|$)/m],

    # ``double-quoted''
    [:double, :constrained, /(^|[^\w;:}])(?:\[([^\]]+?)\])?``(\S|\S.*?\S)''(?=\W|$)/m],

    # 'emphasis'
    [:emphasis, :constrained, /(^|[^\w;:}])(?:\[([^\]]+?)\])?'(\S|\S.*?\S)'(?=\W|$)/m],

    # `single-quoted'
    [:single, :constrained, /(^|[^\w;:}])(?:\[([^\]]+?)\])?`(\S|\S.*?\S)'(?=\W|$)/m],

    # ++monospaced++
    [:monospaced, :unconstrained, /\\?(?:\[([^\]]+?)\])?\+\+(.+?)\+\+/m],

    # +monospaced+
    [:monospaced, :constrained, /(^|[^\w;:}])(?:\[([^\]]+?)\])?\+(\S|\S.*?\S)\+(?=\W|$)/m],

    # __emphasis__
    [:emphasis, :unconstrained, /\\?(?:\[([^\]]+?)\])?\_\_(.+?)\_\_/m],

    # _emphasis_
    [:emphasis, :constrained, /(^|[^\w;:}])(?:\[([^\]]+?)\])?_(\S|\S.*?\S)_(?=\W|$)/m],

    # ##unquoted##
    [:none, :unconstrained, /\\?(?:\[([^\]]+?)\])?##(.+?)##/m],

    # #unquoted#
    [:none, :constrained, /(^|[^\w;:}])(?:\[([^\]]+?)\])?#(\S|\S.*?\S)#(?=\W|$)/m],

    # ^superscript^
    [:superscript, :unconstrained, /\\?(?:\[([^\]]+?)\])?\^(.+?)\^/m],

    # ~subscript~
    [:subscript, :unconstrained, /\\?(?:\[([^\]]+?)\])?\~(.+?)\~/m]
  ]

  # NOTE in Ruby 1.8.7, [^\\] does not match start of line,
  # so we need to match it explicitly
  # order is significant
  REPLACEMENTS = [
    # (C)
    [/\\?\(C\)/, '&#169;', :none],
    # (R)
    [/\\?\(R\)/, '&#174;', :none],
    # (TM)
    [/\\?\(TM\)/, '&#8482;', :none],
    # foo -- bar
    [/(^|\n| |\\)--( |\n|$)/, '&#8201;&#8212;&#8201;', :none],
    # foo--bar
    [/(\w)\\?--(?=\w)/, '&#8212;', :leading],
    # ellipsis
    [/\\?\.\.\./, '&#8230;', :leading],
    # apostrophe or a closing single quote (planned)
    [/([#{CC_ALPHA}])\\?'(?!')/, '&#8217;', :leading],
    # an opening single quote (planned)
    #[/\B\\?'(?=[#{CC_ALPHA}])/, '&#8216;', :none],
    # right arrow ->
    [/\\?-&gt;/, '&#8594;', :none],
    # right double arrow =>
    [/\\?=&gt;/, '&#8658;', :none],
    # left arrow <-
    [/\\?&lt;-/, '&#8592;', :none],
    # right left arrow <=
    [/\\?&lt;=/, '&#8656;', :none],
    # restore entities
    [/\\?(&)amp;((?:[a-zA-Z]+|#\d{2,4}|#x[a-fA-F0-9]{2,4});)/, '', :bounding]
  ]

  # Public: Parse the AsciiDoc source input into an Asciidoctor::Document
  #
  # Accepts input as an IO (or StringIO), String or String Array object. If the
  # input is a File, information about the file is stored in attributes on the
  # Document object.
  #
  # input   - the AsciiDoc source as a IO, String or Array.
  # options - a String, Array or Hash of options to control processing (default: {})
  #           String and Array values are converted into a Hash.
  #           See Asciidoctor::Document#initialize for details about options.
  #
  # returns the Asciidoctor::Document
  def self.load(input, options = {})
    if (monitor = options.fetch(:monitor, false))
      start = ::Time.now.to_f
    end

    attrs = (options[:attributes] ||= {})
    if attrs.is_a?(::Hash) || (RUBY_ENGINE_JRUBY && attrs.is_a?(::Java::JavaUtil::Map))
      # all good; placed here as optimization
    elsif attrs.is_a? ::Array
      attrs = options[:attributes] = attrs.inject({}) do |accum, entry|
        k, v = entry.split '=', 2
        accum[k] = v || ''
        accum
      end
    elsif attrs.is_a? ::String
      # convert non-escaped spaces into null character, so we split on the
      # correct spaces chars, and restore escaped spaces
      attrs = attrs.gsub(REGEXP[:space_delim], "\\1\0").gsub(REGEXP[:escaped_space], '\1')

      attrs = options[:attributes] = attrs.split("\0").inject({}) do |accum, entry|
        k, v = entry.split '=', 2
        accum[k] = v || ''
        accum
      end
    elsif attrs.respond_to?('keys') && attrs.respond_to?('[]')
      # convert it to a Hash as we know it
      original_attrs = attrs
      attrs = options[:attributes] = {}
      original_attrs.keys.each do |key|
        attrs[key] = original_attrs[key]
      end
    else
      raise ::ArgumentError, "illegal type for attributes option: #{attrs.class.ancestors}"
    end

    lines = nil
    if input.is_a? ::File
      lines = input.readlines
      input_mtime = input.mtime
      input_path = ::File.expand_path(input.path)
      # hold off on setting infile and indir until we get a better sense of their purpose
      attrs['docfile'] = input_path
      attrs['docdir'] = ::File.dirname(input_path)
      attrs['docname'] = ::File.basename(input_path, ::File.extname(input_path))
      attrs['docdate'] = docdate = input_mtime.strftime('%Y-%m-%d')
      attrs['doctime'] = doctime = input_mtime.strftime('%H:%M:%S %Z')
      attrs['docdatetime'] = %(#{docdate} #{doctime})
    elsif input.respond_to?(:readlines)
      input.rewind rescue nil
      lines = input.readlines
    elsif input.is_a?(::String)
      lines = input.lines.entries
    elsif input.is_a?(::Array)
      lines = input.dup
    else
      raise ::ArgumentError, "Unsupported input type: #{input.class}"
    end

    if monitor
      read_time = ::Time.now.to_f - start
      start = ::Time.now.to_f
    end

    doc = Document.new(lines, options) 
    if monitor
      parse_time = ::Time.now.to_f - start
      monitor[:read] = read_time
      monitor[:parse] = parse_time
      monitor[:load] = read_time + parse_time
    end
    doc
  end

  # Public: Parse the contents of the AsciiDoc source file into an Asciidoctor::Document
  #
  # Accepts input as an IO, String or String Array object. If the
  # input is a File, information about the file is stored in
  # attributes on the Document.
  #
  # input   - the String AsciiDoc source filename
  # options - a String, Array or Hash of options to control processing (default: {})
  #           String and Array values are converted into a Hash.
  #           See Asciidoctor::Document#initialize for details about options.
  #
  # returns the Asciidoctor::Document
  def self.load_file(filename, options = {})
    ::Asciidoctor.load(::File.new(filename), options)
  end

  # Public: Parse the AsciiDoc source input into an Asciidoctor::Document and render it
  # to the specified backend format
  #
  # Accepts input as an IO, String or String Array object. If the
  # input is a File, information about the file is stored in
  # attributes on the Document.
  #
  # If the :in_place option is true, and the input is a File, the output is
  # written to a file adjacent to the input file, having an extension that
  # corresponds to the backend format. Otherwise, if the :to_file option is
  # specified, the file is written to that file. If :to_file is not an absolute
  # path, it is resolved relative to :to_dir, if given, otherwise the
  # Document#base_dir. If the target directory does not exist, it will not be
  # created unless the :mkdirs option is set to true. If the file cannot be
  # written because the target directory does not exist, or because it falls
  # outside of the Document#base_dir in safe mode, an IOError is raised.
  #
  # If the output is going to be written to a file, the header and footer are
  # rendered unless specified otherwise (writing to a file implies creating a
  # standalone document). Otherwise, the header and footer are not rendered by
  # default and the rendered output is returned.
  #
  # input   - the String AsciiDoc source filename
  # options - a String, Array or Hash of options to control processing (default: {})
  #           String and Array values are converted into a Hash.
  #           See Asciidoctor::Document#initialize for details about options.
  #
  # returns the Document object if the rendered result String is written to a
  # file, otherwise the rendered result String
  def self.render(input, options = {})
    in_place = options.delete(:in_place) || false
    to_file = options.delete(:to_file)
    to_dir = options.delete(:to_dir)
    mkdirs = options.delete(:mkdirs) || false
    monitor = options.fetch(:monitor, false)

    write_in_place = in_place && input.is_a?(::File)
    write_to_target = to_file || to_dir
    stream_output = !to_file.nil? && to_file.respond_to?(:write)

    if write_in_place && write_to_target
      raise ::ArgumentError, 'the option :in_place cannot be used with either the :to_dir or :to_file option'
    end

    if !options.has_key?(:header_footer) && (write_in_place || write_to_target)
      options[:header_footer] = true
    end

    doc = ::Asciidoctor.load(input, options)

    if to_file == '/dev/null'
      return doc
    elsif write_in_place
      to_file = ::File.join(::File.dirname(input.path), "#{doc.attributes['docname']}#{doc.attributes['outfilesuffix']}")
    elsif !stream_output && write_to_target
      working_dir = options.has_key?(:base_dir) ? ::File.expand_path(options[:base_dir]) : ::File.expand_path(::Dir.pwd)
      # QUESTION should the jail be the working_dir or doc.base_dir???
      jail = doc.safe >= SafeMode::SAFE ? working_dir : nil
      if to_dir
        to_dir = doc.normalize_system_path(to_dir, working_dir, jail, :target_name => 'to_dir', :recover => false)
        if to_file
          to_file = doc.normalize_system_path(to_file, to_dir, nil, :target_name => 'to_dir', :recover => false)
          # reestablish to_dir as the final target directory (in the case to_file had directory segments)
          to_dir = ::File.dirname(to_file)
        else
          to_file = ::File.join(to_dir, "#{doc.attributes['docname']}#{doc.attributes['outfilesuffix']}")
        end
      elsif to_file
        to_file = doc.normalize_system_path(to_file, working_dir, jail, :target_name => 'to_dir', :recover => false)
        # establish to_dir as the final target directory (in the case to_file had directory segments)
        to_dir = ::File.dirname(to_file)
      end

      if !::File.directory? to_dir
        if mkdirs
          ::FileUtils.mkdir_p to_dir
        else
          raise ::IOError, "target directory does not exist: #{to_dir}"
        end
      end
    end

    start = ::Time.now.to_f if monitor
    output = doc.render

    if monitor
      render_time = ::Time.now.to_f - start
      monitor[:render] = render_time
      monitor[:load_render] = monitor[:load] + render_time
    end

    if to_file
      start = ::Time.now.to_f if monitor
      if stream_output
        to_file.write output.rstrip
        # ensure there's a trailing endline
        to_file.write EOL
      else
        ::File.open(to_file, 'w') {|file| file.write output }
        # these assignments primarily for testing, diagnostics or reporting
        doc.attributes['outfile'] = outfile = ::File.expand_path(to_file)
        doc.attributes['outdir'] = ::File.dirname(outfile)
      end
      if monitor
        write_time = ::Time.now.to_f - start
        monitor[:write] = write_time
        monitor[:total] = monitor[:load_render] + write_time
      end

      # NOTE document cannot control this behavior if safe >= SafeMode::SERVER
      if !stream_output && doc.safe < SafeMode::SECURE && (doc.attr? 'basebackend-html') &&
          (doc.attr? 'linkcss') && (doc.attr? 'copycss')
        copy_asciidoctor_stylesheet = DEFAULT_STYLESHEET_KEYS.include?(stylesheet = (doc.attr 'stylesheet'))
        copy_user_stylesheet = !copy_asciidoctor_stylesheet && !stylesheet.to_s.empty?
        copy_coderay_stylesheet = (doc.attr? 'source-highlighter', 'coderay') && (doc.attr 'coderay-css', 'class') == 'class'
        copy_pygments_stylesheet = (doc.attr? 'source-highlighter', 'pygments') && (doc.attr 'pygments-css', 'class') == 'class'
        if copy_asciidoctor_stylesheet || copy_user_stylesheet || copy_coderay_stylesheet || copy_pygments_stylesheet
          outdir = doc.attr('outdir')
          stylesoutdir = doc.normalize_system_path(doc.attr('stylesdir'), outdir,
              doc.safe >= SafeMode::SAFE ? outdir : nil)
          Helpers.mkdir_p stylesoutdir if mkdirs
          if copy_asciidoctor_stylesheet
            ::File.open(::File.join(stylesoutdir, DEFAULT_STYLESHEET_NAME), 'w') {|f|
              f.write HTML5.default_asciidoctor_stylesheet
            }
          end

          if copy_user_stylesheet
            if (stylesheet_src = (doc.attr 'copycss')).empty?
              stylesheet_src = doc.normalize_system_path stylesheet
            else
              stylesheet_src = doc.normalize_system_path stylesheet_src
            end
            stylesheet_dst = doc.normalize_system_path stylesheet, stylesoutdir, (doc.safe >= SafeMode::SAFE ? outdir : nil)
            unless stylesheet_src == stylesheet_dst || (stylesheet_content = doc.read_asset stylesheet_src).nil?
              ::File.open(stylesheet_dst, 'w') {|f|
                f.write stylesheet_content
              }
            end
          end

          if copy_coderay_stylesheet
            ::File.open(::File.join(stylesoutdir, 'asciidoctor-coderay.css'), 'w') {|f|
              f.write HTML5.default_coderay_stylesheet
            }
          end

          if copy_pygments_stylesheet
            ::File.open(::File.join(stylesoutdir, 'asciidoctor-pygments.css'), 'w') {|f|
              f.write HTML5.pygments_stylesheet(doc.attr 'pygments-style')
            }
          end
        end
      end
      doc
    else
      output
    end
  end

  # Public: Parse the contents of the AsciiDoc source file into an Asciidoctor::Document
  # and render it to the specified backend format
  #
  # input   - the String AsciiDoc source filename
  # options - a String, Array or Hash of options to control processing (default: {})
  #           String and Array values are converted into a Hash.
  #           See Asciidoctor::Document#initialize for details about options.
  #
  # returns the Document object if the rendered result String is written to a
  # file, otherwise the rendered result String
  def self.render_file(filename, options = {})
    ::Asciidoctor.render(::File.new(filename), options)
  end

  # autoload
  unless RUBY_ENGINE_OPAL
    autoload :Debug,   'asciidoctor/debug'
    autoload :VERSION, 'asciidoctor/version'
  end

  # modules
  require 'asciidoctor/helpers'
  require 'asciidoctor/substitutors'

  # abstract classes
  require 'asciidoctor/abstract_node'
  require 'asciidoctor/abstract_block'

  # concrete classes
  require 'asciidoctor/attribute_list'
  require 'asciidoctor/block'
  require 'asciidoctor/callouts'
  require 'asciidoctor/document'
  require 'asciidoctor/inline'
  require 'asciidoctor/lexer'
  require 'asciidoctor/list'
  require 'asciidoctor/path_resolver'
  require 'asciidoctor/reader'
  require 'asciidoctor/renderer'
  require 'asciidoctor/section'
  require 'asciidoctor/table'

  # backends
  if RUBY_ENGINE_OPAL
    require 'asciidoctor/backends/html5-erb'
  end
end
