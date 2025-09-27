require 'json'
require 'artwork'

describe Artwork do
  before :all do
    @html = [
      File.read("files/van-gogh-paintings.html"),
      File.read("files/claude-monet-paintings.html"),
      File.read("files/pablo-picasso-paintings.html"),
    ]

    # tokenize html
    @tokens = @html.map {|x| tokenize(x)}
    
    # parse html into a tree
    @parsed = @tokens.zip(@html).map {|tokens, html| Html.parse(tokens, html)}
    
    # define a pattern of tags and search for that pattern in the html
    pattern = ["div",
               ["a",
                ["img"],
                ["div",
                 ["div"],
                 ["div"]]]]
    @matches = @parsed.map {|x| x[0].find(pattern)}
    
    # parse each tag which matched the pattern into an Artwork
    @artworks = @matches.map {|match| match.map {|x| Artwork.from_div(x)}}
    
    # create json result from Artwork list
    @json = @artworks.map {|x| JSON.pretty_generate({artworks: x})}
  end

  it "parses van gogh" do
    expect(@artworks[0][0]).to be_a(Artwork)
  end

  it "parses claude monet" do
    expect(@artworks[1][0]).to be_a(Artwork)
  end

  it "parses pablo picasso" do
    expect(@artworks[2][0]).to be_a(Artwork)
  end

  it "parses van gogh - artwork name" do
    expect(@artworks[0][0].name).to eq("The Starry Night")
  end

  it "parses van gogh - artwork year" do
    expect(@artworks[0][0].extensions[0]).to eq("1889")
  end

  it "parses van gogh - artwork link" do
    expect(@artworks[0][0].link).to eq("https://www.google.com/search?sca_esv=c2e426814f4d07e9&gl=us&hl=en&q=The+Starry+Night&stick=H4sIAAAAAAAAAONgFuLQz9U3MI_PNVLiBLFMzC3jC7WUspOt9Msyi0sTc-ITi0qQmJnFJVbl-UXZxYtYBUIyUhWCSxKLiioV_DLTM0oAdKX0-E4AAAA&sa=X&ved=2ahUKEwjK-K-JwLWKAxXcQTABHePpOFoQtq8DegQIMxAD")
  end

  it "parses van gogh - artwork image" do
    expect(@artworks[0][0].image).to eq("data:image/gif;base64,R0lGODlhAQABAIAAAP///////yH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==")
  end
end
