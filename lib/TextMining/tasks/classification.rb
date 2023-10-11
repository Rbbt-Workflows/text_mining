module TextMining
  input :positive_docids, :array, "Positive DocIDs"
  input :negative_docids, :array, "Positive DocIDs"
  input :annotation_types, :array, "Annotation type to process", []
  dep :annotids, :docids => :positive_docids, :annotation_types => :annotation_types
  dep :fine_tune, :docids => :positive_docids, :annotids => :annotids
  task :classifier => :tsv do |positive_docids,negative_docids,annotation_types|
    checkpoint = step(:fine_tune).load

    deepspeed = {}

    model = HuggingfaceModel.new "SequenceClassification", checkpoint, file('model'),
      :annotation_types => annotation_types, 
      :training_args => {fp16: true, deepspeed: deepspeed},
      :corpus_path => corpus.persistence_path

    model.extract_features do |docid,docid_list|
      corpus = Document::Corpus.setup(@model_options[:corpus_path])
      if docid
        DocID.setup(docid, :corpus => corpus)
        document = docid.document
        annotids = @model_options[:annotation_types].collect{|type| document.send(type) }.flatten
        res = nil
        Transformed.with_transform(document, annotids, Proc.new{|a| "[#{a.type}]"} ) do 
          res = document.dup
        end
        res
      else
        DocID.setup(docid_list, :corpus => corpus)
        annotids = @model_options[:annotation_types].collect{|type| docid_list.send(type) }.flatten
        features = []
        docid_list.collect do |docid|
          document = docid.document
          document_annotids = annotids.select{|a| a.docid == docid }
          Transformed.with_transform(document, document_annotids, Proc.new{|a| "[#{a.type}]"} ) do 
            features << document.dup
          end
        end
        features
      end
    end

    docids = []
    labels = []

    model.add_list positive_docids, [1] * positive_docids.length
    model.add_list negative_docids, [0] * negative_docids.length

    model.cross_validation(5)
  end

  input :positive_pmids, :array, "Positive PMIDS"
  input :negative_pmids, :array, "Positive PMIDS"
  dep :load_pmids, :pmids => :positive_pmids
  dep :load_pmids, :pmids => :negative_pmids
  dep_task :pmid_classifier, TextMining, :classifier, :positive_docids => :placeholder, :negative_docids => :placeholder do |jobname,options,dependencies|
    positive_docids, negative_docids = dependencies.flatten

    {:inputs => options.merge(:positive_docids => positive_docids, :negative_docids => negative_docids)}
  end
  

end

