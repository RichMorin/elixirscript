function create_code(json){
  return escodegen.generate(JSON.parse(json));
}