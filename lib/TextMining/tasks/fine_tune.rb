Document.define :cheap_sentences => :single do
  self.split(".")
end
module TextMining

  input :docids, :array, "List of DocID to process"
  input :checkpoint, :string, "Chekpoint dir or name to load"
  dep :annotids
  task :fine_tune => :string do |docids,checkpoint|
    checkpoint ||= "microsoft/BiomedNLP-PubMedBERT-base-uncased-abstract-fulltext"
    mlm = MaskedLMModel.new checkpoint, file(:model), 
      :training_args => {:per_device_train_batch_size => 1},
      :tokenizer_args => {:model_max_length => 128, truncation: true}
    
    annotids = AnnotID.setup(step(:annotids).load)

    if annotids && ! annotids.empty?
      mod, tokenizer = mlm.init

      types = annotids.collect{|s| s.type }.uniq

      types.each do |type|
        token = "[#{type}]"
        if tokenizer.vocab[token].nil?
          tokenizer.add_tokens(token)
        end
      end

      mod.resize_token_embeddings(tokenizer.__len__)
    else
      annotids = []
    end

    prob = 0.15
    docids = DocID.setup(docids, :corpus => corpus)
    docids.extend AnnotatedArray
    documents = docids.document

    documents.each do |document|
      document.cheap_sentences.each do |sentence|
        Transformed.with_transform(sentence, annotids, Proc.new{|a| "[#{a.type}]"}) do 
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
    raise

    mlm.train

    mlm.file('model/model')
  end

end
