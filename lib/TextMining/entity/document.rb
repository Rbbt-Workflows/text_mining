require 'rbbt/entity'
require 'rbbt/document'
require 'rbbt/document/annotation'
require 'rbbt/segment/named_entity'
begin
  require 'rbbt/nlp/open_nlp/sentence_splitter'
  require 'rbbt/ner/g_norm_plus'
rescue Exception
end
require 'TextMining/entity/ner'

%w(banner dictionary).each do |method|
  name = "genes_#{method}"
  Document.define name.to_sym do 
    text = self
    next [] if text.nil? or text.strip.empty?

    ner = TextMining.get_ner(method)

    mentions = ner.match(text)

    if method.to_s == 'dictionary'
      mentions.each do |mention|
        code = mention.code
        mention.code = "Ensembl Gene ID:#{code}" unless code =~ /Ensembl/
      end
    end

    mentions
  end

  norm_name = "norm_#{name}"
  Document.define norm_name.to_sym do 
    mentions = self.send(name)

    next mentions if method.to_s == 'dictionary'

    norm = TextMining.get_norm(organism)

    mentions.each do |mention|
      code = norm.resolve(mention)
      mention.code = code.nil? || code.empty? ? nil : ["Ensembl Gene ID", code] * ":"
    end

    mentions.reject{|mention| mentions.code.nil? }
  end

  Document.persist name, :annotations
  Document.persist norm_name, :annotations
end

Document.define_multiple :ner_gnp do |list|
  list = Annotated.purge(list)
  cpus = Rbbt::Config.get(:cpus, :gnp_ner, :GNormPlus, :GNP, :gnp, :default => 2).to_i

  chunk_size = 20
  num_chunks = list.length / chunk_size

  chunks = Misc.divide list, num_chunks
  texts = TSV.setup({}, "PMID~Text#:type=:single")

  res = TSV.traverse chunks, :cpus => cpus, :bar => true, :into => {} do |documents|
    texts = TSV.setup({}, "PMID~Text#:type=:single")
    documents.each do |document|
      texts[Misc.digest(document)] = document
    end

    begin
      GNormPlus.entities(texts)
    rescue
      Log.warn "GNormPlus error processing chunk"
      res = {}
      documents.each do |document|
        texts = TSV.setup({}, "PMID~Text#:type=:single")
        texts[Misc.digest(document)] = document
        begin
          res.merge!(GNormPlus.entities(texts))
        rescue
          Log.warn "GNormPlus error processing document: #{document}"
          res[Misc.digest(document)] = []
        end
      end
      res
    end
  end

  list.collect do |document|
    res[Misc.digest(document)].select{|m| m.entity_type == "Gene" }
  end
end

Document.define_multiple :genes_gnp do |list|
  Document.setup(list)
  list.ner_gnp.collect do |mentions|
    mentions.select{|m| m.entity_type == "Gene" }
  end
end

Document.define_multiple "norm_genes_gnp" do |list|
  Document.setup(list)
  doc_mentions = list.genes_gnp

  norm = TextMining.get_norm(TextMining.organism)

  doc_mentions.collect do |mentions|
    mentions.each do |mention|
      code = norm.resolve(mention)
      mention.code = code.nil? || code.empty? ? nil : ["Ensembl Gene ID", code] * ":"
    end
    mentions.reject{|mention| mention.code.nil? }
  end
end

Document.persist :genes_gnp, :annotations
Document.persist :norm_genes_gnp, :annotations
