
API.add 'service/lantern/test',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.service.lantern.test(this.queryParams.verbose)

API.service.lantern.test = (verbose) ->
  result = {passed:[],failed:[]}

  tests = [
    () ->
      result.processed = API.service.lantern.process doi: '10.1186/1758-2946-3-47'
      console.log result.processed
      return _.isEqual result.processed, API.service.lantern.test._examples.result
    () ->
      result.csv = API.service.lantern.csv [result.processed]
      return result.csv is API.service.lantern.test._examples.csv
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose
  return result

# TODO check that the below result is the same as the current live system (except intentionally introduced differences)
API.service.lantern.test._examples = {
  result: {
    "_id": undefined,
    "pmcid": "PMC3206455",
    "pmid": "21999661",
    "doi": "10.1186/1758-2946-3-47",
    "title": "Open bibliography for science, technology, and medicine.",
    "journal_title": "Journal of Cheminformatics",
    "pure_oa": false,
    "issn": "1758-2946",
    "eissn": "1758-2946",
    "publication_date": "2011-01-01T00:00:00Z",
    "electronic_publication_date": "2011-10-14T00:00:00Z",
    "publisher": undefined,
    "publisher_licence": "not applicable",
    "licence": "cc-by",
    "epmc_licence": "cc-by",
    "licence_source": "epmc_xml_permissions",
    "epmc_licence_source": "epmc_xml_permissions",
    "in_epmc": true,
    "epmc_xml": true,
    "aam": false,
    "open_access": true,
    "ahead_of_print": undefined,
    "romeo_colour": "unknown",
    "preprint_embargo": "unknown",
    "preprint_self_archiving": "unknown",
    "postprint_embargo": "unknown",
    "postprint_self_archiving": "unknown",
    "publisher_copy_embargo": "unknown",
    "publisher_copy_self_archiving": "unknown",
    "authors": [
      {
        "fullName": "Jones R",
        "firstName": "Richard",
        "lastName": "Jones",
        "initials": "R"
      },
      {
        "fullName": "Macgillivray M",
        "firstName": "Mark",
        "lastName": "Macgillivray",
        "initials": "M"
      },
      {
        "fullName": "Murray-Rust P",
        "firstName": "Peter",
        "lastName": "Murray-Rust",
        "initials": "P",
        "authorId": {
          "type": "ORCID",
          "value": "0000-0003-3386-3972"
        }
      },
      {
        "fullName": "Pitman J",
        "firstName": "Jim",
        "lastName": "Pitman",
        "initials": "J"
      },
      {
        "fullName": "Sefton P",
        "firstName": "Peter",
        "lastName": "Sefton",
        "initials": "P",
        "authorId": {
          "type": "ORCID",
          "value": "0000-0002-3545-944X"
        }
      },
      {
        "fullName": "O'Steen B",
        "firstName": "Ben",
        "lastName": "O'Steen",
        "initials": "B",
        "authorId": {
          "type": "ORCID",
          "value": "0000-0002-5175-7789"
        }
      },
      {
        "fullName": "Waites W",
        "firstName": "William",
        "lastName": "Waites",
        "initials": "W"
      }
    ],
    "in_core": true,
    "repositories": [
      {
        "name": "Springer - Publisher Connector",
        "fulltexts": []
      }
    ],
    "grants": [],
    "confidence": 1,
    "score": 0,
    "provenance": [
      "Added PMCID from EUPMC",
      "Added PMID from EUPMC",
      "Added article title from EUPMC",
      "Confirmed is in EUPMC",
      "Confirmed is open access from EUPMC",
      "Added journal title from EUPMC",
      "Added issn from EUPMC",
      "Added eissn from EUPMC",
      "Added date of publication from EUPMC",
      "Added electronic publication date from EUPMC",
      "Confirmed fulltext XML is available from EUPMC",
      "Added EPMC licence (cc-by) from epmc_xml_permissions. The bit that let us determine the licence was: thisisanopenaccessarticledistributedunderthetermsofthecreativecommonsattributionlicense . If licence statements contain URLs we will try to find those in addition to searching for the statement's text. Here the entire licence statement was: This is an Open Access article distributed under the terms of the Creative Commons Attribution License .",
      "Added author list from EUPMC",
      "Checked author manuscript status in EUPMC, found no evidence of being one",
      "Unable to obtain information about this article from Crossref.",
      "Found DOI in CORE",
      "Searched OpenDOAR but could not find repo and/or URL",
      "Added repositories that CORE claims article is available from",
      "Not attempting Grist API grant lookups since no grants data was obtained from EUPMC.",
      "Not checking ahead of print status on pubmed. The article is already in EUPMC.",
      "Could not find journal in DOAJ",
      "Unable to add any data from Sherpa Romeo.",
      "Not attempting to retrieve licence data via article publisher splash page lookup."
    ],
    "compliance_wellcome_standard": true,
    "compliance_wellcome_deluxe": true
  },
  "csv": "\"pmcid\",\"pmid\",\"doi\",\"title\",\"journal_title\",\"pure_oa\",\"issn\",\"eissn\",\"publication_date\",\"electronic_publication_date\",\"publisher\",\"publisher_licence\",\"licence\",\"epmc_licence\",\"licence_source\",\"epmc_licence_source\",\"in_epmc\",\"epmc_xml\",\"aam\",\"open_access\",\"ahead_of_print\",\"romeo_colour\",\"preprint_embargo\",\"preprint_self_archiving\",\"postprint_embargo\",\"postprint_self_archiving\",\"publisher_copy_embargo\",\"publisher_copy_self_archiving\",\"authors\",\"in_core\",\"repositories\",\"grants\",\"confidence\",\"score\",\"provenance\",\"compliance_wellcome_standard\",\"compliance_wellcome_deluxe\",\"PMCID\",\"PMID\",\"DOI\",\"Article title\",\"Journal title\",\"Pure Open Access\",\"ISSN\",\"EISSN\",\"Publication Date\",\"Electronic Publication Date\",\"Publisher\",\"Publisher Licence\",\"Licence\",\"EPMC Licence\",\"Licence Source\",\"EPMC Licence Source\",\"Fulltext in EPMC?\",\"XML Fulltext?\",\"AAM?\",\"Open Access\",\"Ahead of Print?\",\"Sherpa Romeo Colour\",\"Preprint Embargo\",\"Preprint Self-Archiving Policy\",\"Postprint Embargo\",\"Postprint Self-Archiving Policy\",\"Publisher's Copy Embargo\",\"Publisher's Copy Self-Archiving Policy\",\"Author(s)\",\"In CORE?\",\"Archived Repositories\",\"Repository URLs\",\"Repository OAI IDs\",\"Repository Fulltext URLs\",\"Correct Article Confidence\",\"Lantern Score\",\"Compliance Wellcome Standard\",\"Compliance Wellcome Deluxe\",\"Provenance\"\n\"PMC3206455\",\"21999661\",\"10.1186/1758-2946-3-47\",\"Open bibliography for science, technology, and medicine.\",\"Journal of Cheminformatics\",false,\"1758-2946\",\"1758-2946\",\"2011-01-01T00:00:00Z\",\"2011-10-14T00:00:00Z\",\"unknown\",\"not applicable\",\"cc-by\",\"cc-by\",\"epmc_xml_permissions\",\"epmc_xml_permissions\",true,true,false,true,\"unknown\",\"unknown\",\"unknown\",\"unknown\",\"unknown\",\"unknown\",\"unknown\",\"unknown\",\"[{\"\"fullName\"\":\"\"Jones R\"\",\"\"firstName\"\":\"\"Richard\"\",\"\"lastName\"\":\"\"Jones\"\",\"\"initials\"\":\"\"R\"\"},{\"\"fullName\"\":\"\"Macgillivray M\"\",\"\"firstName\"\":\"\"Mark\"\",\"\"lastName\"\":\"\"Macgillivray\"\",\"\"initials\"\":\"\"M\"\"},{\"\"fullName\"\":\"\"Murray-Rust P\"\",\"\"firstName\"\":\"\"Peter\"\",\"\"lastName\"\":\"\"Murray-Rust\"\",\"\"initials\"\":\"\"P\"\",\"\"authorId\"\":{\"\"type\"\":\"\"ORCID\"\",\"\"value\"\":\"\"0000-0003-3386-3972\"\"}},{\"\"fullName\"\":\"\"Pitman J\"\",\"\"firstName\"\":\"\"Jim\"\",\"\"lastName\"\":\"\"Pitman\"\",\"\"initials\"\":\"\"J\"\"},{\"\"fullName\"\":\"\"Sefton P\"\",\"\"firstName\"\":\"\"Peter\"\",\"\"lastName\"\":\"\"Sefton\"\",\"\"initials\"\":\"\"P\"\",\"\"authorId\"\":{\"\"type\"\":\"\"ORCID\"\",\"\"value\"\":\"\"0000-0002-3545-944X\"\"}},{\"\"fullName\"\":\"\"O'Steen B\"\",\"\"firstName\"\":\"\"Ben\"\",\"\"lastName\"\":\"\"O'Steen\"\",\"\"initials\"\":\"\"B\"\",\"\"authorId\"\":{\"\"type\"\":\"\"ORCID\"\",\"\"value\"\":\"\"0000-0002-5175-7789\"\"}},{\"\"fullName\"\":\"\"Waites W\"\",\"\"firstName\"\":\"\"William\"\",\"\"lastName\"\":\"\"Waites\"\",\"\"initials\"\":\"\"W\"\"}]\",true,\"[{\"\"name\"\":\"\"Springer - Publisher Connector\"\",\"\"fulltexts\"\":[]}]\",\"[]\",1,0,\"[\"\"Added PMCID from EUPMC\"\",\"\"Added PMID from EUPMC\"\",\"\"Added article title from EUPMC\"\",\"\"Confirmed is in EUPMC\"\",\"\"Confirmed is open access from EUPMC\"\",\"\"Added journal title from EUPMC\"\",\"\"Added issn from EUPMC\"\",\"\"Added eissn from EUPMC\"\",\"\"Added date of publication from EUPMC\"\",\"\"Added electronic publication date from EUPMC\"\",\"\"Confirmed fulltext XML is available from EUPMC\"\",\"\"Added EPMC licence (cc-by) from epmc_xml_permissions. The bit that let us determine the licence was: thisisanopenaccessarticledistributedunderthetermsofthecreativecommonsattributionlicense . If licence statements contain URLs we will try to find those in addition to searching for the statement's text. Here the entire licence statement was: This is an Open Access article distributed under the terms of the Creative Commons Attribution License .\"\",\"\"Added author list from EUPMC\"\",\"\"Checked author manuscript status in EUPMC, found no evidence of being one\"\",\"\"Unable to obtain information about this article from Crossref.\"\",\"\"Found DOI in CORE\"\",\"\"Searched OpenDOAR but could not find repo and/or URL\"\",\"\"Added repositories that CORE claims article is available from\"\",\"\"Not attempting Grist API grant lookups since no grants data was obtained from EUPMC.\"\",\"\"Not checking ahead of print status on pubmed. The article is already in EUPMC.\"\",\"\"Could not find journal in DOAJ\"\",\"\"Unable to add any data from Sherpa Romeo.\"\",\"\"Not attempting to retrieve licence data via article publisher splash page lookup.\"\"]\",true,true,\"PMC3206455\",\"21999661\",\"10.1186/1758-2946-3-47\",\"Open bibliography for science, technology, and medicine.\",\"Journal of Cheminformatics\",\"FALSE\",\"1758-2946\",\"1758-2946\",\"2011-01-01T00:00:00Z\",\"2011-10-14T00:00:00Z\",\"Unknown\",\"not applicable\",\"cc-by\",\"cc-by\",\"epmc_xml_permissions\",\"epmc_xml_permissions\",\"TRUE\",\"TRUE\",\"FALSE\",\"TRUE\",\"Unknown\",\"Unknown\",\"Unknown\",\"Unknown\",\"Unknown\",\"Unknown\",\"Unknown\",\"Unknown\",\"Jones R, Macgillivray M, Murray-Rust P, Pitman J, Sefton P, O'Steen B, Waites W\",\"TRUE\",\"Springer - Publisher Connector\",\"undefined\",\"undefined\",\"\",1,0,\"TRUE\",\"TRUE\",\"Added PMCID from EUPMC\r\nAdded PMID from EUPMC\r\nAdded article title from EUPMC\r\nConfirmed is in EUPMC\r\nConfirmed is open access from EUPMC\r\nAdded journal title from EUPMC\r\nAdded issn from EUPMC\r\nAdded eissn from EUPMC\r\nAdded date of publication from EUPMC\r\nAdded electronic publication date from EUPMC\r\nConfirmed fulltext XML is available from EUPMC\r\nAdded EPMC licence (cc-by) from epmc_xml_permissions. The bit that let us determine the licence was: thisisanopenaccessarticledistributedunderthetermsofthecreativecommonsattributionlicense . If licence statements contain URLs we will try to find those in addition to searching for the statement's text. Here the entire licence statement was: This is an Open Access article distributed under the terms of the Creative Commons Attribution License .\r\nAdded author list from EUPMC\r\nChecked author manuscript status in EUPMC, found no evidence of being one\r\nUnable to obtain information about this article from Crossref.\r\nFound DOI in CORE\r\nSearched OpenDOAR but could not find repo and/or URL\r\nAdded repositories that CORE claims article is available from\r\nNot attempting Grist API grant lookups since no grants data was obtained from EUPMC.\r\nNot checking ahead of print status on pubmed. The article is already in EUPMC.\r\nCould not find journal in DOAJ\r\nUnable to add any data from Sherpa Romeo.\r\nNot attempting to retrieve licence data via article publisher splash page lookup.\""
}