require 'rbbt'
require 'rbbt/workflow'
require 'rbbt/sources/organism'
require 'rbbt/document'
require 'rbbt/document/corpus'


#Workflow.require_workflow "Translation"
#Workflow.require_workflow "ExTRI2"
module TextMining
  extend Workflow

  CORPUS = Document::Corpus.setup(Rbbt.var.TextMining.corpus.find)
  ANNOTATIONS = Rbbt.var.TextMining.annotations.find
  ANNOTATION_REPO = Rbbt.var.TextMining.annotation_repo.find

  def self.organism
    "Hsa/feb2014"
  end

  helper :corpus do 
    TextMining::CORPUS
  end

end

require 'TextMining/entity/document'

require 'TextMining/tasks/corpus'
require 'TextMining/tasks/annotations'
require 'TextMining/tasks/fine_tune'
require 'TextMining/tasks/classification'
