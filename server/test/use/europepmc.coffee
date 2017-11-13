
API.add 'use/europepmc/test',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.use.europepmc.test(this.queryParams.verbose)

API.use.europepmc.test = (verbose) ->
  result = {passed:[],failed:[]}

  pmcid = '3206455'
  tests = [
    () ->
      result.eupmc = API.use.europepmc.pmc pmcid
      return _.isEqual result.eupmc, API.use.europepmc.test._examples.record
    () ->
      result.aam = API.use.europepmc.authorManuscript pmcid
      return result.aam.aam is false
    () ->
      result.licence = API.use.europepmc.licence pmcid
      return _.isEqual result.licence, API.use.europepmc.test._examples.licence
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose
  return result


API.use.europepmc.test._examples = {
  "licence": {
    "retrievable": true,
    "licence": "cc-by",
    "match": "This is an Open Access article distributed under the terms of the Creative Commons Attribution License",
    "matched": "thisisanopenaccessarticledistributedunderthetermsofthecreativecommonsattributionlicense",
    "source": "epmc_xml_permissions"
  },
  "record": {
    "id": "21999661",
    "source": "MED",
    "pmid": "21999661",
    "pmcid": "PMC3206455",
    "doi": "10.1186/1758-2946-3-47",
    "title": "Open bibliography for science, technology, and medicine.",
    "authorString": "Jones R, Macgillivray M, Murray-Rust P, Pitman J, Sefton P, O'Steen B, Waites W.",
    "authorList": {
      "author": [
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
      ]
    },
    "authorIdList": {
      "authorId": [
        {
          "type": "ORCID",
          "value": "0000-0003-3386-3972"
        },
        {
          "type": "ORCID",
          "value": "0000-0002-3545-944X"
        },
        {
          "type": "ORCID",
          "value": "0000-0002-5175-7789"
        }
      ]
    },
    "journalInfo": {
      "volume": "3",
      "journalIssueId": 1823303,
      "dateOfPublication": "2011 ",
      "monthOfPublication": 0,
      "yearOfPublication": 2011,
      "printPublicationDate": "2011-01-01",
      "journal": {
        "title": "Journal of Cheminformatics",
        "medlineAbbreviation": "J Cheminform",
        "essn": "1758-2946",
        "issn": "1758-2946",
        "isoabbreviation": "J Cheminform",
        "nlmid": "101516718"
      }
    },
    "pubYear": "2011",
    "pageInfo": "47",
    "abstractText": "The concept of Open Bibliography in science, technology and medicine (STM) is introduced as a combination of Open Source tools, Open specifications and Open bibliographic data. An Openly searchable and navigable network of bibliographic information and associated knowledge representations, a Bibliographic Knowledge Network, across all branches of Science, Technology and Medicine, has been designed and initiated. For this large scale endeavour, the engagement and cooperation of the multiple stakeholders in STM publishing - authors, librarians, publishers and administrators - is sought.",
    "affiliation": "Departments of Statistics and Mathematics, University of California, Berkeley, CA, USA. pitman@stat.berkeley.edu.",
    "language": "eng",
    "pubModel": "Electronic",
    "pubTypeList": {
      "pubType": [
        "research-article",
        "Journal Article"
      ]
    },
    "fullTextUrlList": {
      "fullTextUrl": [
        {
          "availability": "Open access",
          "availabilityCode": "OA",
          "documentStyle": "pdf",
          "site": "Europe_PMC",
          "url": "http://europepmc.org/articles/PMC3206455?pdf=render"
        },
        {
          "availability": "Open access",
          "availabilityCode": "OA",
          "documentStyle": "html",
          "site": "Europe_PMC",
          "url": "http://europepmc.org/articles/PMC3206455"
        },
        {
          "availability": "Free",
          "availabilityCode": "F",
          "documentStyle": "pdf",
          "site": "PubMedCentral",
          "url": "https://www.ncbi.nlm.nih.gov/pmc/articles/pmid/21999661/pdf/?tool=EBI"
        },
        {
          "availability": "Free",
          "availabilityCode": "F",
          "documentStyle": "html",
          "site": "PubMedCentral",
          "url": "https://www.ncbi.nlm.nih.gov/pmc/articles/pmid/21999661/?tool=EBI"
        },
        {
          "availability": "Subscription required",
          "availabilityCode": "S",
          "documentStyle": "doi",
          "site": "DOI",
          "url": "https://doi.org/10.1186/1758-2946-3-47"
        }
      ]
    },
    "isOpenAccess": "Y",
    "inEPMC": "Y",
    "inPMC": "Y",
    "hasPDF": "Y",
    "hasBook": "N",
    "hasSuppl": "Y",
    "citedByCount": 3,
    "hasReferences": "N",
    "hasTextMinedTerms": "Y",
    "hasDbCrossReferences": "N",
    "hasLabsLinks": "Y",
    "license": "cc by",
    "authMan": "N",
    "epmcAuthMan": "N",
    "nihAuthMan": "N",
    "hasTMAccessionNumbers": "N",
    "dateOfCompletion": "2011-11-10",
    "dateOfCreation": "2011-11-02",
    "dateOfRevision": "2012-11-09",
    "electronicPublicationDate": "2011-10-14",
    "firstPublicationDate": "2011-10-14"
  }
}