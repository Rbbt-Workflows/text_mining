require 'rbbt-util'
require 'rbbt/workflow'
require 'test/unit'

class TestWorkflow < Test::Unit::TestCase
  def workflow
    @@workflow ||= Workflow.require_workflow __FILE__.sub('test_','')
  end

  def last_job
    task_name = workflow.tasks.keys.last
    workflow.job(task_name)
  end

  def first_job
    task_name = workflow.tasks.keys.first
    workflow.job(task_name)
  end

  def test_true
    Log.severity = 0
    positive_pmids =<<~EOF.split("\n")
    10022128
    10022519
    10022610
    10022617
    10022815
    10022869
    10022878
    10022897
    10022915
    10022926
    EOF

    negative_pmids =<<~EOF.split("\n")
    12107561
    22809631
    20561206
    9452295
    15029253
    18568407
    9041854
    14744868
    10406461
    9099702
    EOF
    positive_docids = workflow.job(:load_pmids, :pmids => positive_pmids).run
    negative_docids = workflow.job(:load_pmids, :pmids => negative_pmids).run
    workflow.job(:classifier, :positive_docids => positive_docids, :negative_docids => negative_docids, :annotation_types => %w(genes_dictionary)).run
  end
end

