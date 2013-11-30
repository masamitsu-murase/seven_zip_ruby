module SevenZipRuby
  class ArchiveInfo
    def initialize(method, solid, num_blocks, header_size, phy_size)
      @method, @solid, @num_blocks, @header_size, @phy_size =
        method, solid, num_blocks, header_size, phy_size
    end

    attr_reader :method, :num_blocks, :header_size, :phy_size

    alias size phy_size
    alias block_num num_blocks

    def solid?
      return @solid
    end

    def inspect
      "#<ArchiveInfo: #{method}, #{size}byte>"
    end
  end
end
