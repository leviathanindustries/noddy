

# at 17/01/2016 dissemin searches crossref, base, sherpa/romeo, zotero primarily,
# and arxiv, hal, pmc, openaire, doaj, perse, cairn.info, numdam secondarily via oa-pmh
# see http://dissem.in/sources
# http://dev.dissem.in/api.html

API.use ?= {}
API.use.dissemin = {}

API.add 'use/dissemin/doi/:doipre/:doipost',
  get: () -> return API.use.dissemin.doi this.urlParams.doipre + '/' + this.urlParams.doipost


API.use.dissemin.doi = (doi) ->
  url = 'http://beta.dissem.in/api/' + doi
  API.log 'Using dissemin for ' + url
  res = API.http.cache doi, 'dissemin_doi'
  if not res?
    try
      res = HTTP.call('GET', url).data.paper
      res.url = API.http.resolve res.pdf_url
      API.http.cache doi, 'dissemin_doi', res
  try res.redirect = API.service.oab.redirect res.url
  return res



API.use.dissemin.status = () ->
  try
    h = HTTP.call('GET', 'http://beta.dissem.in/api/10.1186/1758-2946-3-47',{timeout:3000})
    return if h.data.paper then true else h.data
  catch err
    return err.toString()

API.use.dissemin.test = (verbose) ->
  result = {passed:[],failed:[]}
  tests = [
    () ->
      result.record = HTTP.call('GET', 'http://beta.dissem.in/api/10.1186/1758-2946-3-47').data.paper
      return _.isEqual result.record, API.use.dissemin.test._examples.record
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose
  return result



API.use.dissemin.test._examples = {
  record:{
    "classification": "OA",
    "title": "Open Bibliography for Science, Technology, and Medicine",
    "pdf_url": "http://dx.doi.org/10.1186/1758-2946-3-47",
    "records": [
      {
        "splash_url": "http://orcid.org/0000-0003-3386-3972",
        "identifier": "orcid:0000-0003-3386-3972:10.1186/1758-2946-3-47",
        "type": "journal-article",
        "source": "orcid"
      },
      {
        "splash_url": "https://doi.org/10.1186/1758-2946-3-47",
        "doi": "10.1186/1758-2946-3-47",
        "publisher": "Springer Science + Business Media",
        "issue": "1",
        "journal": "Journal of Cheminformatics",
        "pdf_url": "http://dx.doi.org/10.1186/1758-2946-3-47",
        "volume": "3",
        "source": "crossref",
        "policy": {
          "romeo_id": "195",
          "preprint": "can",
          "postprint": "can",
          "published": "can"
        },
        "identifier": "oai:crossref.org:10.1186/1758-2946-3-47",
        "type": "journal-article",
        "pages": "47",
        "issn": "1758-2946"
      },
      {
        "splash_url": "https://www.researchgate.net/publication/51722444_Open_Bibliography_for_Science_Technology_and_Medicine",
        "doi": "10.1186/1758-2946-3-47",
        "contributors": "",
        "abstract": "The concept of Open Bibliography in science, technology and medicine (STM) is introduced as a combination of Open Source tools, Open specifications and Open bibliographic data. An Openly searchable and navigable network of bibliographic information and associated knowledge representations, a Bibliographic Knowledge Network, across all branches of Science, Technology and Medicine, has been designed and initiated. For this large scale endeavour, the engagement and cooperation of the multiple stakeholders in STM publishing - authors, librarians, publishers and administrators - is sought.",
        "pdf_url": "https://www.researchgate.net/profile/Peter_Sefton/publication/51722444_Open_Bibliography_for_Science_Technology_and_Medicine/links/09e41509765a2be42d000000.pdf",
        "source": "researchgate",
        "keywords": "",
        "identifier": "oai:researchgate.net:51722444",
        "type": "journal-article"
      },
      {
        "splash_url": "http://www.dspace.cam.ac.uk/handle/1810/239926",
        "doi": "10.1186/1758-2946-3-47",
        "contributors": "",
        "abstract": "Abstract The concept of Open Bibliography in science, technology and medicine (STM) is introduced as a combination of Open Source tools, Open specifications and Open bibliographic data. An Openly searchable and navigable network of bibliographic information and associated knowledge representations, a Bibliographic Knowledge Network, across all branches of Science, Technology and Medicine, has been designed and initiated. For this large scale endeavour, the engagement and cooperation of the multiple stakeholders in STM publishing - authors, librarians, publishers and administrators - is sought. ; RIGHTS : This article is licensed under the BioMed Central licence at http://www.biomedcentral.com/about/license which is similar to the 'Creative Commons Attribution Licence'. In brief you may : copy, distribute, and display the work; make derivative works; or make commercial use of the work - under the following conditions: the original author must be given credit; for any reuse or distribution, it must be made clear to others what the license terms of this work are.",
        "source": "base",
        "keywords": "",
        "identifier": "ftunivcam:oai:www.dspace.cam.ac.uk:1810/239926",
        "type": "journal-article"
      },
      {
        "splash_url": "http://www.dspace.cam.ac.uk/handle/1810/238394",
        "contributors": "",
        "abstract": "The concept of Open Bibliography in science, technology and medicine (STM) is introduced as a combination of Open Source tools, Open specifications and Open bibliographic data. An Openly searchable and navigable network of bibliographic information and associated knowledge representations, a Bibliographic Knowledge Network, across all branches of Science, Technology and Medicine, has been designed and initiated. For this large scale endeavour, the engagement and cooperation of the multiple stakeholders in STM publishing - authors, librarians, publishers and administrators - is sought. BibJSON, a simple structured text data format (informed by BibTex, Dublin Core, PRISM and JSON) suitable for both serialisation and storage of large quantities of bibliographic data is presented. BibJSON, and companion bibliographic software systems BibServer and OpenBiblio promote the quantity and quality of Openly available bibliographic data, and encourage the development of improved algorithms and services for processing the wealth of information and knowledge embedded in bibliographic data across all fields of scholarship. Major providers of bibliographic information have joined in promoting the concept of Open Bibliography and in working together to create prototype nodes for the Bibliographic Knowledge Network. These contributions include large-scale content from PubMed and ArXiv, data available from Open Access publishers, and bibliographic collections generated by the members of the project. The concept of a distributed bibliography (BibSoup) is explored.",
        "source": "base",
        "keywords": "bibliography Open citation semantics BibJSON publishers",
        "identifier": "ftunivcam:oai:www.dspace.cam.ac.uk:1810/238394",
        "type": "journal-article"
      },
      {
        "splash_url": "http://www.jcheminf.com/content/3/1/47",
        "contributors": "",
        "abstract": "Abstract The concept of Open Bibliography in science, technology and medicine (STM) is introduced as a combination of Open Source tools, Open specifications and Open bibliographic data. An Openly searchable and navigable network of bibliographic information and associated knowledge representations, a Bibliographic Knowledge Network, across all branches of Science, Technology and Medicine, has been designed and initiated. For this large scale endeavour, the engagement and cooperation of the multiple stakeholders in STM publishing - authors, librarians, publishers and administrators - is sought.",
        "pdf_url": "http://www.jcheminf.com/content/3/1/47",
        "source": "base",
        "keywords": "",
        "identifier": "ftbiomed:oai:biomedcentral.com:1758-2946-3-47",
        "type": "journal-article"
      }
    ],
    "authors": [
      {
        "name": {
          "last": "Jones",
          "first": "Richard"
        }
      },
      {
        "name": {
          "last": "MacGillivray",
          "first": "Mark"
        }
      },
      {
        "orcid": "0000-0003-3386-3972",
        "name": {
          "last": "Murray-Rust",
          "first": "Peter"
        }
      },
      {
        "name": {
          "last": "Pitman",
          "first": "Jim"
        }
      },
      {
        "name": {
          "last": "Sefton",
          "first": "Peter"
        }
      },
      {
        "name": {
          "last": "O'Steen",
          "first": "Ben"
        }
      },
      {
        "name": {
          "last": "Waites",
          "first": "William"
        }
      }
    ],
    "date": "2011-01-01",
    "type": "journal-article"
  }
}