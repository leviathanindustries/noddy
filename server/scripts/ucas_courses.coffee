
import Future from 'fibers/future'
import fs from 'fs'

API.add 'scripts/ucas/courses',
  get: 
    authRequired: 'root'
    action: () ->
      institutions = JSON.parse fs.readFileSync '/home/cloo/institutions.json'
      addr = 'https://digital.ucas.com/search/results?SearchText=&SubjectText=&ProviderText=&AutoSuggestType=&SearchType=&SortOrder=CourseTitleAtoZ&PreviouslyAppliedFilters=SMM_0_Full-time__QM_2_Bachelor+degrees+%28with+or+without+Honours%29__QM_3_Masters+degrees__EP_6_1__&AcademicYearId=2019&ClearingOptOut=True&vacancy-rb=rba&filters=Destination_Undergraduate&UcasTariffPointsMin=0&UcasTariffPointsMax=144%2B&ProviderText=&SubjectText=&filters=StudyModeMapped_Full-time&PointOfEntry=1&filters=QualificationMapped_Bachelor+degrees+%28with+or+without+Honours%29&filters=QualificationMapped_Masters+degrees&DistanceFromPostcode=25mi&RegionDistancePostcode=&CurrentView=Course&__RequestVerificationToken=ImS3Q-N9kqOn_SuVXXyia8Og-auOw6TsghSKSxCwKqEkmhpLn0bDdbYMQxYygmHcLXhQYJbeK6yr76xz39SwM4KejJEJ4xNYfOeuEFnSu9w1'
      courses = [] # many courses are duplicate names at different unis, so this will not be as big as the loop below
      errors = []
      instituted = []
  
      for institution in institutions
        iaddr = addr.replace 'ProviderText=&', 'ProviderText=' + institution.replace(/ /g,'+') + '&'
        counter = 0
        pg = API.http.puppeteer iaddr
        len = parseInt pg.split(' courses from ')[0].split('>').pop()
        pages = Math.floor len/30
        while counter <= pages
          # 30 results per page, 29413 courses to get
          # but discovered it only pages to 333 then errors out (search index prob caps at 10k) ...
          # hence why we iterate over a list of institutions then scrape within those searches
          console.log institution + ' ' + counter + ' of ' + len + ' in ' + pages + ' pages, ' + courses.length + ' total courses and ' + errors.length + ' errors'
          try
            parts = pg.split '<h3 class="course-title heading--snug" data-course-primary-id="'
            parts.shift()
            for p in parts
              course = p.split('>')[1].split('</h3>')[0].trim().split('\n')[0].replace(/&amp;/g,'&')
              courses.push(course) if course not in courses
          catch
            errors.push caddr
          
          counter += 1
          caddr = iaddr + '&pageNumber=' + counter
          pg = API.http.puppeteer caddr
          instituted.push institution
          
          future = new Future()
          Meteor.setTimeout (() -> future.return()), 1000
          future.wait()

      courses.sort()
      
      try
        fs.writeFileSync '/home/cloo/ucas_courses.json', JSON.stringify courses, null, 2

      try
        fs.writeFileSync '/home/cloo/ucas_errors.json', JSON.stringify errors, null, 2

      API.mail.send
        to: 'alert@cottagelabs.com'
        subject: 'UCAS courses complete'
        text: 'courses: ' + courses.length + '\nerrors: ' + errors.length + '\ninstitutions: ' + instituted.length

      return courses
