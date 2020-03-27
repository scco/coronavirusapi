# README

### Development Environment Requirements

- Ruby 2.7.0 (If you have trouble switching ruby versions with Bundler, the application runs fine with Ruby 2.5.5 - just update the version locally in your Gemfile)
- MySQL
- yarn (https://classic.yarnpkg.com/en/docs/install)
- bundle (gem install bundler)

### Setting up a development environment

1.) Clone the repository from https://github.com/coronavirusapi/coronavirusapi

2.) Create a MySQL user for the application to use. 

2b.) If you want an application specific user (recommended), create databases coronavirusapi_development, coronavirusapi_production, and coronavirusapi_test and grant the MySQL user permissions on those tables. 

3.) Copy db/database.yml.example to db/database.yml and update the file with your database credentials

4.) Import the database dump from db/dump.sql using the command:
 
 `mysql -u <mysql-username> -p coronavirusapi_development < ~/projects/cvirusapi/coronavirusapi/db/dump.sql`
 
5.) Run `bundle exec rails db:migrate RAILS_ENV=development`

6.) Run `bundle exec rails s` to start the development server

7.) Access the application at localhost:3000