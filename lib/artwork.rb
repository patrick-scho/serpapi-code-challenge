require 'cgi'

# Token Struct for tokenizing html into <tags>
Token = Struct.new(:value, :from, :to)

# find the next instance of c that is not surrounded by quotes
# using a regex because loops are too slow
def find_next_not_in_str(str, offset, c)
  # regex that matches either a quoted string *or* the character
  # causing all strings to be skipped
  regex = Regexp.new(/(?:"[^"]*")|(#{Regexp.escape(c)})/)
  
  # we match as long as match[1] (which is c) is not matched
  # continually increasing the offset from where we look
  match = str.match(regex, offset)
  while match
    if match[1]
      return match.begin(1)
    end

    offset = match.end(0)
    match = str.match(regex, offset)
  end

  return nil
end

# tokenize string into a series of <tags>
# script and style tags are skipped because
# they are hard to parse and we dont need their content
def tokenize(str)
  result = []
  offset = 0
  while offset < str.length
    # find opening and closing <>
    from = str.index('<', offset)
    to = find_next_not_in_str(str, from, '>')
    break unless from && to # only continue if we find both

    # add our new token to the result list
    result.push(Token.new(str[from..to], from, to))
    offset = to + 1

    # for script and style tags we look for the closing tag
    # and add it "manually", and skip everything in between
    ["script", "style"].each do |x|
      if result[-1].value.start_with? "<#{x}"
        end_from = str.index("</#{x}>", offset)
        result.push(Token.new("</#{x}>", end_from, end_from + x.length + 2))
        offset = end_from + x.length + 3
      end
    end
  end
  return result
end

# Attr Struct that represents a key="value"
# in a tag like <a href="">
Attr = Struct.new(:name, :value)

# Tag class forming the html tree
class Tag
  attr_reader :token
  attr_accessor :name
  attr_accessor :attrs
  attr_accessor :children
  attr_accessor :content
  attr_accessor :closed

  def initialize(token, name, attrs)
    @token = token
    @name = name
    @attrs = attrs
    @closed = false
  end

  # utility function that can print tags recursively
  # effectively
  def print(indent = 0)
    puts("#{' '*indent}<#{@name}#{(@attrs||[]).map {|a| " #{a.name}=\"#{a.value}\""}.join}>")
    if @content
      puts("#{' '*(indent+2)}#{@content}")
    end
    if @children
      @children.each {|c| c.print(indent + 2)}
    end
    puts("#{' '*indent}</#{@name}>")
  end

  # parse a tag, extracting its name and attribute pairs
  def self.parse(token)
    # get the name, bounded by a space or >
    # (in the latter case we look from the end)
    str = token.value[1..-2]
    name_end = str.index(' ') || 0
    name = str[0..name_end-1]

    # we parse attributes only if name_end != 0
    # (there is something after the name)
    attrs = []
    if name_end != 0 && str[0] != '!'
      # search attribute using regex
      match = str[name_end..-1].scan(/\s[^=]+="[^"]*"/)
      attrs = match.map {|m| Attr.new(m[1...m.index('=')], m[m.index('=')+2..-2])}
    end
    return Tag.new(token, name, attrs)
  end

  # try matching pattern once on this tag specifically,
  # recursively checking children as well
  # returns the matched tag
  def find_one(pattern)
    # compare name
    return nil unless @name == pattern[0]
    if @children
      # compare number of children
      return nil unless @children.length == pattern.length-1
      # invoke find_one for each child
      @children.each_with_index do |c, i|
        return nil unless c.find_one(pattern[i+1])
      end
    else
      # check no children
      return nil unless pattern.length == 1
    end
    return self
  end

  # try matching pattern anywhere, starting with the tag itself
  # and recursively trying all children
  # this way, every tag gets tested against the pattern once
  def find(pattern)
    # try on this tag, if we match we dont need to try
    # any children since they cannot match exactly
    match = self.find_one(pattern)
    if match
      return [match]
    end

    # try children and if they succeed, concat the result
    # to our result list since they might return multiple
    # results
    result = []
    @children&.each do |c|
      match = c.find(pattern)
      if match
        result.concat(match)
      end
    end
    return result
  end
end

class Html
  # parse a list of tokens and the string it was generated from
  # into a tree of Tags
  # we need the string to extract content in between tags like
  # <div>CONTENT</div> since that doesnt get tokenized
  def self.parse(tokens, str)
    tags = []
    tokens.each_with_index do |token, index|
      if token.value[1] == '!' # skip comments and doctype
        next
      elsif token.value[1] != '/' # opening tags
        tags.push(Tag.parse(token))
      else # closing tags
        prev = tags[-1]
        if index > 0 && prev.name == token.value[2..-2] && prev.token == tokens[index-1]
          # if the previously parsed tag matches this one
          # add content from str using the Tags token field
          # which includes indices where it was taken from str
          prev.content = str[prev.token.to+1..token.from-1]
          prev.closed = true # this tag was already matched with a closing tag
        else
          # otherwise go looking for the matching opening tag
          # and transfer the tags in between opening and closing tag
          # into the opening tag as children
          matching = tags.rindex { |tag| tag.name == token.value[2..-2] && !tag.closed }
          tags[matching].children = tags.slice!(matching+1..-1)
          tags[matching].closed = true # this tag was already matched with a closing tag
        end
      end
    end
    return tags
  end
end

class Artwork
  attr_accessor :name
  attr_accessor :extensions
  attr_accessor :link
  attr_accessor :image

  # parse Artwork from div
  def self.from_div(div)
    result = Artwork.new
    result.name = div.children[0].children[1].children[0].content
    result.extensions = [div.children[0].children[1].children[1].content]
    result.link = CGI.unescapeHTML "https://www.google.com#{div.children[0].attrs.find {|x| x.name=="href"}.value}"
    result.image = div.children[0].children[0].attrs.find {|x| x.name=="src"}.value
    return result
  end

  # allow Artwork to be turned into json
  def as_json(options = {})
    {
      name: @name,
      extensions: @extensions,
      link: @link,
      image: @image,
    }
  end

  def to_json(*options)
    JSON.generate(as_json, *options)
  end
end


if __FILE__ == $0

# "main function" if file is directly run
# parse html, find the pattern,
# parse artworks and print json

html = File.read("files/van-gogh-paintings.html")

tokens = tokenize(html)
# tokens.each {|x| puts(x)}

parsed = Html.parse(tokens, html)
# parsed.each {|x| x.print}

pattern = ["div",
           ["a",
            ["img"],
            ["div",
             ["div"],
             ["div"]]]]

matches = parsed[0].find(pattern)
# matches.each {|x| x.print}

artworks = matches.map {|d| Artwork.from_div(d)}
# artworks.each {|x| puts x}

require 'json'
json = JSON.pretty_generate({artworks: artworks})
puts json

end
