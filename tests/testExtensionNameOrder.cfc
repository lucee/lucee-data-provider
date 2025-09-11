component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll(){
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		variables.testVersions = deserializeJson(FileRead("staticArtifacts/testExtensionCoreVersions.json"), false);

		application action="update" mappings={
			"/services" : expandPath( dir & "../apps/updateserver/services" )
		};
		variables.extMetaReader = new services.ExtensionMetadataReader();
		variables.extMetaReader.loadMeta( variables.testVersions );

		variables.compressExt = "8D7FB0DF-08BB-1589-FE3975678F07DB17";
		variables.imageExt   = "B737ABC4-D43F-4D91-8E8E973E37C40D1B";
	}

	function run( testResults , testBox ) {
	describe( "LDEV-5699 test extension listing by name", function() {

			it (title="test extension list is sorted by name (production data)", body=function(){
				// Load production-like data from static artifact
				var dir = getDirectoryFromPath(getCurrentTemplatePath());
				// Lucee will convert {COLUMNS,DATA} JSON to a query automatically
				var qry = deserializeJson(FileRead("staticArtifacts/testExtensionNameOrder.json"), false);
				expect(qry).toBeQuery();
				
				// Use a fresh reader to ensure no caching effects
				var extMetaReader = new services.ExtensionMetadataReader();
				extMetaReader.loadMeta(qry);
				var extQuery = extMetaReader.list();
				var names = [];
				for (var i=1; i <= extQuery.recordCount; i++) {
					arrayAppend(names, extQuery.name[i]);
				}
				var sortedNames = duplicate(names);
				arraySort(sortedNames, "textnocase");
				expect(names).toBe(sortedNames);
			});

			it (title="test extension list is sorted by name (fresh reader)", body=function(){
				var dir = getDirectoryFromPath(getCurrentTemplatePath());
				var testVersions = deserializeJson(FileRead("staticArtifacts/testExtensionCoreVersions.json"), false);
				var extMetaReader = new services.ExtensionMetadataReader();
				extMetaReader.loadMeta(testVersions);
				var extQuery = extMetaReader.list();
				var names = [];
				for (var i=1; i <= extQuery.recordCount; i++) {
					arrayAppend(names, extQuery.name[i]);
				}
				var sortedNames = duplicate(names);
				arraySort(sortedNames, "textnocase");
				expect(names).toBe(sortedNames);
			});

			it (title="test extension list is sorted by name (randomized input)", body=function(){
				var dir = getDirectoryFromPath(getCurrentTemplatePath());
				var testVersions = deserializeJson(FileRead("staticArtifacts/testExtensionCoreVersions.json"), false);
				// Randomize the order of the query rows
				var rows = [];
				for (var i=1; i <= testVersions.recordCount; i++) {
					arrayAppend(rows, i);
				}
				arrayShuffle(rows);
				var randomized = queryNew(testVersions.columnList);
				for (var idx in rows) {
					queryAddRow(randomized);
					for (var col in listToArray(testVersions.columnList)) {
						randomized[col][randomized.recordCount] = testVersions[col][rows[idx]];
					}
				}
				var extMetaReader = new services.ExtensionMetadataReader();
				extMetaReader.loadMeta(randomized);
				var extQuery = extMetaReader.list();
				var names = [];
				for (var i=1; i <= extQuery.recordCount; i++) {
					arrayAppend(names, extQuery.name[i]);
				}
				var sortedNames = duplicate(names);
				arraySort(sortedNames, "textnocase");
				expect(names).toBe(sortedNames);
			});

			it (title="test extension list is sorted by name (reverse input)", body=function(){
				var dir = getDirectoryFromPath(getCurrentTemplatePath());
				var testVersions = deserializeJson(FileRead("staticArtifacts/testExtensionCoreVersions.json"), false);
				// Reverse the order of the query rows
				var rows = [];
				for (var i=testVersions.recordCount; i >= 1; i--) {
					arrayAppend(rows, i);
				}
				var reversed = queryNew(testVersions.columnList);
				for (var idx in rows) {
					queryAddRow(reversed);
					for (var col in listToArray(testVersions.columnList)) {
						reversed[col][reversed.recordCount] = testVersions[col][rows[idx]];
					}
				}
				var extMetaReader = new services.ExtensionMetadataReader();
				extMetaReader.loadMeta(reversed);
				var extQuery = extMetaReader.list();
				var names = [];
				for (var i=1; i <= extQuery.recordCount; i++) {
					arrayAppend(names, extQuery.name[i]);
				}
				var sortedNames = duplicate(names);
				arraySort(sortedNames, "textnocase");
				expect(names).toBe(sortedNames);
			});
		});
	}

	// Fisher-Yates shuffle
	private function arrayShuffle(arr) {
		for (var i = arrayLen(arr); i > 1; i--) {
			var j = randRange(1, i);
			var tmp = arr[i];
			arr[i] = arr[j];
			arr[j] = tmp;
		}
		return arr;
	}
}
