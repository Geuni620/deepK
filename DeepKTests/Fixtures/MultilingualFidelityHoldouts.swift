import Foundation
@main struct FidelityHoldouts {
 static func main() async throws {
  guard CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--live" else {
   print("Usage: FidelityHoldouts --live <cases.json> <result.json>"); return
  }
  struct Sample: Decodable { let source: String; let target: String; let input: String }
  let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
  let client = ClaudeTranslationClient(configuration:.init(transport:.streamOnDemand))
  let names=["ja":"Japanese","ko":"Korean (한국어)","zh-Hans":"Simplified Chinese","zh-Hant":"Traditional Chinese (Taiwan)"]
  var rows:[[String:String]]=[]
  for sample in samples {
   let source = sample.source, target = sample.target, text = sample.input
   let output=try await client.translate(text:text,source:names[source]!,target:target,model:"claude-haiku-5-5")
   rows.append(["source":source,"target":target,"input":text,"output":output,"fidelityRevisions":String(await client.lastFidelityRevisionCount)])
   let data=try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
   try data.write(to:URL(fileURLWithPath:CommandLine.arguments[3]),options:.atomic)
   print("Completed",rows.count,"of",samples.count);fflush(stdout)
  }
  await client.disconnect()
 }
}
