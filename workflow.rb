require 'rbbt'
require 'rbbt/workflow'
require 'rbbt/resource'
require 'rbbt/sources/organism'
require 'rbbt/sources/pubmed'
require 'rbbt/ner/segment/named_entity'
require 'rbbt/sources/jochem'
require 'rbbt/ner/linnaeus'
require 'rbbt/ner/abner'
require 'rbbt/ner/banner'
require 'rbbt/ner/rnorm'
require 'rbbt/ner/ngram_prefix_dictionary'
require 'rbbt/nlp/open_nlp/sentence_splitter'

Workflow.require_workflow "Translation"
module TextMining
  extend Workflow

  Rbbt.claim Rbbt.software.opt.bibtex2html, :install, Rbbt.share.install.software.bibtex2html.find

  NER_METHODS = {}
  NORM = {}

  def self.get_ner(method)
    method = method.to_s.downcase
    if not TextMining::NER_METHODS.include?(method) or TextMining::NER_METHODS[method].nil?
      TextMining::NER_METHODS[method] = case method
                              when 'abner'
                                Abner.new
                              when 'banner'
                                Banner.new
                              when 'dictionary'
                                NGramPrefixDictionary.new Organism.lexicon(Organism.default_code("Hsa")), "Ensembl Gene ID"
                              when 'jochem'
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
    @@jochem_norm ||= JoChem.identifiers.tsv :persist => true, :unnamed => true, :fields => [field], :type => :flat
  end

  def self.get_organism_ner
    Linnaeus
  end

  input :text, :text, "Text to process"
  def self.split_sentences(text)
    sentences = OpenNLP.sentence_splitter(text)
    sentences
  end
  task :split_sentences=> :annotations
  export_exec :split_sentences


  input :text, :text, "Text to process"
  input :method, :select, "Gene NER method to use", :abner, :select_options => ['abner', 'banner', 'dictionary']
  input :normalize, :boolean, "Try to normalize entities", false
  input :organism, :string, "Organism to use for the normalization", Organism.default_code("Hsa")
  def self.gene_mention_recognition(text, method, normalize, organism)
    return [] if text.nil? or text.strip.empty?
    ner = get_ner(method)

    mentions = ner.match(text)

    case
    when method.to_s == 'dictionary'
      mentions.each do |mention|
        code = mention.code
        mention.code = "Ensembl Gene ID:#{code}" unless code =~ /Ensembl/
      end
    when normalize
      norm = get_norm(organism)

      mentions.each do |mention|
        code = norm.resolve(mention)
        mention.code = code.nil? ? nil : ["Ensembl Gene ID", code] * ":"
      end

    end

    mentions
  end
  task :gene_mention_recognition => :annotations
  export_synchronous :gene_mention_recognition

  input :text, :text, "Text to process"
  input :method, :select, "Compound NER method to use", :JoChem, :select_options => ['JoChem']
  input :format, :select, "Format to normalize to", "Compound Name", :select_options => JoChem.identifiers.fields
  def self.compound_mention_recognition(text, method, format = "Compound Name")
    return [] if text.nil? or text.strip.empty?

    ner = get_ner(method)

    mentions = ner.match(text)

    norm = get_jochem_norm(format)
    mentions.each do |m|
      next if m.code.nil?
      code = m.code.split(":").last
      other = norm[code]
      if other.nil? or other.empty?
        m.code = nil
      else
        m.code = [format, other * "|"] * ":"
      end
    end

    mentions
  end
  task :compound_mention_recognition => :annotations
  export_exec :compound_mention_recognition

  input :text, :text, "Text to process"
  def self.species_mention_recognition(text)
    return [] if text.nil? or text.strip.empty?

    ner = get_organism_ner

    mentions = ner.match(text)

    mentions
  end
  task :species_mention_recognition => :annotations
  export_exec :species_mention_recognition

  input :pmids, :array, "List of PMIDs"
  task :pmid_citation => :array do |pmids|

    bibtex = PubMed.get_article(pmids).values_at(*pmids).collect{|article|
      article.bibtex
    } * "\n\n"
    Rbbt.software.opt.bibtex2html.produce
    TmpFile.with_file(bibtex, true, :extension => 'bib') do |bibfile|
      CMD.cmd("#{Rbbt.software.opt.bibtex2html.bin.bibtex2html.find} '#{ bibfile }'")
    end
    
  end
  export_exec :pmid_citation

  input :reference_terms, :array, "Reference terms"
  input :un_normalized, :array, "Un-normalized terms"
  task :normalize_terms => :tsv do |reference_terms,un_normalized|
    #reference_terms = TSV.setup(Hash[*reference_terms.zip(reference_terms).flatten], :type => :single)
    reference_terms = TSV.setup(reference_terms, :type => :list, :key_field => "Reference")
    reference_terms.add_field "Term" do |k,v|
      Array === k ? k.first : k
    end
    norm = Normalizer.new reference_terms
    trans = TSV.setup({}, :key_field => "Term", :fields => ["Best reference matches"], :type => :flat)
    missing = 0
    un_normalized.each do |term|
      matches = norm.resolve(term, nil, :threshold => -100)
      trans[term] = matches
    end
    trans
  end
  export_asynchronous :normalize_terms

end

require 'TextMining/tasks/classifcation'
