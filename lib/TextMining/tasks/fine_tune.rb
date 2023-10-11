require 'rbbt/vector/model/huggingface/masked_lm'
module TextMining

  input :docids, :array, "List of DocID to process"
  input :annotids, :array, "List of AnnotID to process"
  input :mask_probability, :float, "Probability for a word being masked", 0.15
  input :checkpoint, :string, "Chekpoint dir or name to load"
  task :fine_tune => :string do |docids,annotids,mask_probability,checkpoint|
    checkpoint ||= "microsoft/BiomedNLP-PubMedBERT-base-uncased-abstract-fulltext"

    tokens = docids.collect{|docid| corpus[docid].split(/ +|[.,]/).length }
    max_model_length = 2
    max_tokens = tokens.sort[tokens.length * 0.8]
    set_info :max_tokens, max_tokens

    max_tokens = max_tokens.to_f
    while max_tokens > 2.2
      max_model_length *= 2
      max_tokens /= 2
    end

    set_info :max_model_length, max_model_length

    deepspeed = { }
    mlm = MaskedLMModel.new checkpoint, file(:model), 
      :training_args => {:per_device_train_batch_size => 1, deepspeed: deepspeed},
      :tokenizer_args => {:model_max_length => max_model_length, truncation: true}
    
    annotids = AnnotID.setup(annotids)

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
    annotids_by_docid = {}
    annotids.each{|a| annotids_by_docid[a.docid] ||= []; annotids_by_docid[a.docid] << a }
    corpus = self.corpus
    TSV.traverse docids, :bar => "Processing documents" do |docid|
      document_annotids = annotids_by_docid[docid] || []
      document = corpus[docid]
      Transformed.with_transform(document, document_annotids, Proc.new{|a| "[#{a.type}]"}) do 
        tokens = document.split(/( +|[.,])/)
        last_mask = false
        masks = tokens.length.times.select do |i| 
          if !last_mask && tokens[i].length > 2 && rand < mask_probability  
            last_mask = true
            true
          else
            last_mask = false if tokens[i].length > 2
            false
          end
        end

        labels = tokens.values_at *masks
        masks.each do |i|
          tokens[i] = "[MASK]"
        end

        masked_document = tokens * ""

        mlm.add masked_document, labels
      end
    end

    mlm.train

    mlm.model_path
  end

end
