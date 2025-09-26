class Token
  def self.parse(str)
  end
end

def find_next_not_in_str(str, start, c)
  in_str = false
  (0..str.length).each do |i|
    if not in_str
      if str[i] == '"'
        in_str = true
      elsif str[i] == c
        return i
      end
    else
      if str[i] == '"' && i > 0 && str[i-1] != '\\'
        in_str = false
      end
    end
  end
  return nil
end

def tokenize(str)
  result = []
  index = 0
  while true
    from = str.index('<')
    to = find_next_not_in_str(str, from, '>')
    break unless from && to

    result.push(str[from..to])
    str = str[to+1..-1]

    ["script", "style"].each do |x|
      if result[-1].start_with? "<#{x}"
        end_index = str.index("</#{x}>")
        str = str[end_index+x.length+3..-1]
        result.push("</#{x}>")
      end
    end
  end
  return result
end

class Attr
  attr_accessor :name
  attr_accessor :value

  def initialize(name, value)
    @name = name
    @value = value
  end
end

class Tag
  attr_accessor :name
  attr_accessor :attrs
  attr_accessor :children

  def initialize(name, attrs)
    @name = name
    @attrs = attrs
  end

  def print(indent = 0)
    puts("#{' '*indent}<#{@name}#{(@attrs||[]).map {|a| " #{a.name} = [#{a.value}]"}.join}>")
    if children
      @children.each {|c| c.print(indent + 2)}
    end
    puts("#{' '*indent}</#{@name}>")
  end

  def self.parse(str)
    name_end = str.index(' ') || 0
    name = str[0..name_end-1]
    attrs = []
    if name_end != 0 && str[0] != '!'
      match = str[name_end..-1].scan(/\s[^=]+="[^"]*"/)
      attrs = match.map {|m| Attr.new(m[1...m.index('=')], m[m.index('=')+2..-2])}
    end
    return Tag.new(name, attrs)
  end
end

class Html
  def self.parse(str)
    tokens = tokenize(str)
    tags = []
    tokens.each do |t|
      if t[1] != '/'
        tags.push(Tag.parse(t[1..-2]))
      else
        if tags[-1].name == t[2..-2]
          # puts("content <#{tags[-1].name}>")
        else
          matching = tags.rindex { |tag| tag.name == t[2..-2] }
          tags[matching].children = tags.slice!(matching+1..-1)
        end
      end
    end
    return tags
  end

  def select_divs(pattern)
  end
end

class Artwork
  def from_div(div)
  end
end


html = File.read("files/van-gogh-paintings.html")
parsed = Html.parse(html)
parsed.each do |x| x.print end

# pattern = []
# divs = @parsed.select_divs(pattern)
#
# artworks = @divs.map {|d| Artwork.from_div(d)}
