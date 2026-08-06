# frozen_string_literal: true

module JekyllObsidian
  # Tracks normalized output destinations while treating a file and any path
  # below that file as a collision. Each insertion visits only its path
  # segments, so large sites do not compare every output with every other one.
  class DestinationRegistry
    Node = Struct.new(:owner, :descendant_owner, :children, keyword_init: true)

    def initialize
      @root = node
    end

    def add(destination, owner)
      current = @root
      lineage = [current]
      destination.split("/").reject(&:empty?).each do |segment|
        return current.owner if current.owner

        current.children[segment] ||= node
        current = current.children.fetch(segment)
        lineage << current
      end

      return current.owner if current.owner
      return current.descendant_owner if current.descendant_owner

      current.owner = owner
      lineage[0...-1].each { |ancestor| ancestor.descendant_owner ||= owner }
      nil
    end

    private

    def node
      Node.new(owner: nil, descendant_owner: nil, children: {})
    end
  end
end
