**DataShark

Make sure you have ruby 3.3.0.**

```
bundle install
ruby setup.rb
```

**Set up the env to set up the api key and other options.**

```
DATABASE_PATH=
CSV_PATH=
API_URL=
SCHEDULE_INTERVAL= example 1s
API_KEY=DELETE_AFTER_PROCESS= boolean
```


**Use the rackup command to run the app**




**Add these params to HikCentral / Access Control dump rule**
Dump rule content:
${Person ID};${First Name};${Last Name};${Department};${Access Date};${Card Swiping Time};${Attendance Status};${Device Name};${Device Serial No.};${Authentication Mode};${Authentication Result};${Card No.};${Card Reader Name};${Direction};${Resource Name}

Content Written Format:
