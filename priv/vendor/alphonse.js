function createCode(json){
  return escodegen.generate(JSON.parse(json));
}