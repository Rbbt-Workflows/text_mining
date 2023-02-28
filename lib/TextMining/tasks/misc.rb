require 'rbbt/resource'
module TextMining
  Rbbt.claim Rbbt.software.opt.bibtex2html, :install, Rbbt.share.install.software.bibtex2html.find

  input :text, :text, "Text to process"
  def self.split_sentences(text)
    sentences = OpenNLP.sentence_splitter(text.dup)
    sentences
  end
  task :split_sentences=> :annotations
  export_exec :split_sentences


  input :text, :text, "Text to process"
  input :method, :select, "Gene NER method to use", :abner, :select_options => ['abner', 'banner', 'dictionary']
  input :normalize, :boolean, "Try to normalize entities", false
  input :organism, :string, "Organism to use for the normalization", TextMining.organism
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
  input :format, :select, "Format to normalize to", "Compound Name"
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
