module TextMining
  input :docids, :array, "DoIDs to process"
  input :annotation_types, :array, "Annotation type to process"
  task :annotations => :annotations do |docids,types|
    documents = docids.collect{|d| corpus[d] }
    documents.extend AnnotatedArray
    Document.setup(documents)
    types.collect do |type|
      documents.send(type)
    end.flatten
  end

  dep :annotations
  task :annotids => :array do
    step(:annotations).path.tsv(:fields => []).keys
  end
end

