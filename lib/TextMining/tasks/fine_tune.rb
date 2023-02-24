
module TextMining

  input :pmids, :array, "List of PMIDs", ExTRI2.job(:relevant_pmids).run[0..1000]
  task :docids => :array do |pmids|
    documents = ExTRI2::CORPUS.add_pmid pmids
    documents.docid
  end

  dep :docids
  task :gene_fine_tune => :string do |pmids|
    checkpoint = "microsoft/BiomedNLP-PubMedBERT-base-uncased-abstract-fulltext"
    mlm = MaskedLMModel.new checkpoint, file(:model), 
      :training_args => {:per_device_train_batch_size => 1},
      :tokenizer_args => {:model_max_length => 128, truncation: true}

    mod, tokenizer = mlm.init

    if tokenizer.vocab["[GENE]"].nil?
      tokenizer.add_tokens("[GENE]")
      mod.resize_token_embeddings(tokenizer.__len__)
    end

    prob = 0.15
    docids = DocID.setup(step(:docids).load, :corpus => ExTRI2::CORPUS)
    documents = docids.document
    documents.each do |document|
      genes = document.gnp
      document.sentences.each do |sentence|
        Transformed.with_transform(sentence, genes, "[GENE]") do 
          tokens = sentence.split(/( +|[^.,])/)
          masks = tokens.length.times.select{|i| tokens[i].length > 2 && rand < prob }

          labels = tokens.values_at *masks
          masks.each do |i|
            tokens[i] = "[MASK]"
          end

          masked_sentence = tokens * ""

          mlm.add masked_sentence, labels
        end
      end
    end

    mlm.train
  end

  dep :gene_fine_tune
  dep ExTRI2, :training_set
  task :classifier => :tsv do
    checkpoint = step(:gene_fine_tune).file('model/model')

    model = HuggingfaceModel.new "SequenceClassification", checkpoint, file(:model)

    model.extract_features do |document,list|
      document.replace_segments(document.gnp, "[GENE]")
    end

    TSV.traverse step(:training_set) do |pmid,label|
      document = ExTRI2::CORPUS.add_pmid pmid
      model.add document, label.to_i
    end

    model.cross_validation(3)
  end

end
