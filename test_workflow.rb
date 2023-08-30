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

  def run_classification(positive_pmids, negative_pmids, annotation_types = nil)
    annotation_types = [] if annotation_types.nil?
    annotation_types = [annotation_types.to_s] unless Array === annotation_types

    positive_docids = workflow.job(:load_pmids, :pmids => positive_pmids).run
    negative_docids = workflow.job(:load_pmids, :pmids => negative_pmids).run

    job = workflow.job(
      :classifier, 
      :positive_docids => positive_docids, :negative_docids => negative_docids,
      :checkpoint => "mrm8488/bert-tiny-finetuned-enron-spam-detection",
      :annotation_types => annotation_types,
    )

    assert_nothing_raised do 
      job.run
    end
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

    cv = run_classification(positive_pmids, negative_pmids, %w(genes_dictionary))

    assert(TSV === cv)
  end

  def test_query
    require 'rbbt/sources/pubmed'
    Log.severity = 0

    max = 500
    q1 = "Cancer"
    q2 = "Stroke"

    positive_pmids = PubMed.query(q1, max)
    negative_pmids = PubMed.query(q2, max)


    cv_orig = run_classification(positive_pmids, negative_pmids)
    cv_genes = run_classification(positive_pmids, negative_pmids, %w(genes_dictionary))

    ppp cv_orig
    ppp cv_genes
  end

  def test_query_larger
    require 'rbbt/sources/pubmed'
    Log.severity = 0

    max = 5000
    q1 = "Bladder AND Cancer AND NOT Lung"
    q2 = "Lung AND Cancer AND NOT Bladder"

    positive_pmids = PubMed.query(q1, max)
    negative_pmids = PubMed.query(q2, max)


    cv_orig = run_classification(positive_pmids, negative_pmids)
    cv_genes = run_classification(positive_pmids, negative_pmids, %w(genes_dictionary))

    ppp cv_orig
    ppp cv_genes
  end
end

