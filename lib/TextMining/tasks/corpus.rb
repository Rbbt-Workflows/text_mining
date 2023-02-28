require 'rbbt/document/corpus/pubmed'
module TextMining

  input :pmids, :array, "PMIDs to load"
  task :load_pmids => :array do |pmids|
    corpus.add_pmid(pmids).docid
  end
end
