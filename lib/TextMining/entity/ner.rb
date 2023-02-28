require 'rbbt/segment/named_entity'
require 'rbbt/ner/rnorm'
require 'rbbt/ner/ngram_prefix_dictionary'

module TextMining
  NER_METHODS = {}
  NORM = {}

  def self.get_ner(method)
    method = method.to_s.downcase
    if not TextMining::NER_METHODS.include?(method) or TextMining::NER_METHODS[method].nil?
      TextMining::NER_METHODS[method] = case method
                              when 'abner'
                                require 'rbbt/ner/abner'
                                Abner.new
                              when 'banner'
                                require 'rbbt/ner/banner'
                                Banner.new
                              when 'dictionary'
                                NGramPrefixDictionary.new Organism.lexicon(TextMining.organism), "Ensembl Gene ID"
                              when 'jochem'
                                require 'rbbt/sources/jochem'
                                NGramPrefixDictionary.new JoChem.lexicon.tsv(:persist => true, :type => :flat, :fields => [1]), "JoChem:Chemical", true
                              else 
                                raise "Method unidentified: #{ method }"
                              end
    else
      TextMining::NER_METHODS[method]
    end
  end

  def self.get_norm(organism)
    if not TextMining::NORM.include?(organism) or TextMining::NORM[organism].nil?
      require 'rbbt/ner/rnorm'
      TextMining::NORM[organism] = Normalizer.new(Organism.lexicon(organism).produce)
    else
      TextMining::NORM[organism]
    end
  end

  def self.get_jochem_norm(field = "Compound Name")
    require 'rbbt/sources/jochem'
    @@jochem_norm ||= JoChem.identifiers.tsv :persist => true, :unnamed => true, :fields => [field], :type => :flat
  end

  def self.get_organism_ner
    require 'rbbt/ner/linnaeus'
    Linnaeus
  end
end
