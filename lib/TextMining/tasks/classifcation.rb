#require 'rbbt/util/python'

module TextMining
  input :training_set, :tsv, "TSV with DocIDs and labels"
  input :annotation_types, :array, "List of annotation types to replace with '[<AnnotId.type>]'"
  input :checkpoint, :string, "Chekpoint dir or name to load"
  task :classifier => :tsv do |training_set,annotation_types,checkpoint|
    checkpoint ||= "microsoft/BiomedNLP-PubMedBERT-base-uncased-abstract-fulltext"
    checkpoint = checkpoint.file('model/model') if Step === checkpoint

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

#module TextMining
#  RbbtPython.add_path Rbbt.python.find(:lib)
#
#  def self.lstm_train(text, labels, embeddings, model_dir)
#    Open.mkdir model_dir
#    RbbtPython.run "LSTM", "train_LTSM" do
#      train_LTSM(texts, labels, embeddings, model_dir)
#    end
#  end
#
#  def self.lstm_predict(text, model_dir)
#    predictions = nil
#    RbbtPython.run "LSTM", "predict_LSTM" do
#      predictions = predict_LSTM(texts, model_dir)
#    end
#    predictions.to_a
#  end
#
#  input :texts, :array, "Training texts"
#  input :labels, :array, "Training labels"
#  input :embeddings, :tsv, "Embeddings"
#  task :lstm_train => :array do |texts, labels, embeddings|
#    model_dir = files_dir
#    TextMining.lstm_train(texts, labels, embeddings, model_dir)
#    Dir.glob(model_dir + '/*')
#  end
#
#  input :texts, :array, "Prediction texts"
#  input :model_dir, :string 
#  task :lstm_predict => :array do |texts, model_dir|
#    TextMining.lstm_predict(texts, model_dir)
#  end
#end
