#!/usr/bin/env Rscript
suppressMessages(library(tidyverse)) # everything else
suppressMessages(library(viridis)) # colorblind friendly
suppressMessages(library(Rmisc)) # multiplot
suppressMessages(library(corrplot)) # plotting correlation magnitudes
suppressMessages(library(PerformanceAnalytics)) # visualizing more correlation stuff

## READ DATA

# set up path and read in raw (use native read.csv for stringAsFactors = True)
setwd("/Users/matthew/github/duolingo")
survey_raw <- read.csv("survey_data.csv") %>% as_tibble()
usage_raw <- read.csv("survey_users_app_usage.csv") %>% as_tibble()

## HELPERS

#' @description clean times by replacing outliers with median. there are no missing values
#' The data comes in extremely skewed but leaves roughly normal (according to qqnorm() lol)
clean_time_spent <- function(time) {
  # Looked at qqnorm() Plot, very non-normal distribution — use median
  outlier_cutoff <- 60 * 60 # seconds # PREVIOUSLy: median(time) + IQR(time) * 1.5
  outliers <- which(time > outlier_cutoff | time < 0) # 13.9% of data are outliers - 89% of those are very high
  time[outliers] <- median(time)
  return(time) 
}

#' @description sets a lower limit on a function and also sets the NA values to that
set_lower_limit <- function(column, at) {
  column[which(column < at) ] <- at
  column[which(is.na(column))] <- at
  return(column)
}

#' @description sets all the max values to the median
ignore_max_value <- function(column) {
  # replace with median, geometric distribution
  column[which(column == max(column))] <- median(column)
  return(column)
}

#' @description sets all NA values to a specified value
replace_na <- function(column, with) {
  column[which(is.na(column))] <- with
  return(column)
}

#' @description replaces all empty values with the specified text
replace_empty <- function(column, with="No Response") {
  levels(column) <- c(levels(column), with) 
  column[which(column == "")] <- with
  column <- droplevels(column)
  return(column)
}

#' @description turns the list of resources into a number of how many
parse_resource_num <- function(column) {
  as.character(column)  %>% 
    sapply(function(s)  {
      sub("(language events, conversation groups, meet-ups, etc.)", "", s) %>% 
        strsplit(",") %>% unlist() %>% length()
      }) 
}

# CLEAN
survey <- survey_raw %>% mutate(
  user_id            = as.character(user_id),
  age                = factor(age, levels=c("No Response", "Under 18", "18-34", "35 - 54", "55 - 74", "75 or older")),
  future_contact     = (future_contact == "Yes"),  # Assume that missing responses are "No", avoid harassment
  survey_complete    = as.logical(survey_complete),
  time_spent_seconds = clean_time_spent(time_spent_seconds), # consider bucketing? idk. somewhat gaussian
  primary_language_motivation_followup = as.character(primary_language_motivation_followup),
  other_resources    = parse_resource_num(other_resources)
) %>%
  group_by(user_id) %>% filter(time_spent_seconds == max(time_spent_seconds)) %>% ungroup() %>%
  # deduplicate by prefering the survey w/longest time by user (31 repeat surveys)... 
  # weird stuff though, like user 35ca57a372c911e98c79dca9049399ef... who are you even
  mutate(
    age                          = replace_na(age, with="No Response"),
    annual_income                = replace_empty(annual_income),
    duolingo_platform            = replace_empty(duolingo_platform, "Unknown"),
    duolingo_subscriber          = replace_empty(duolingo_subscriber),
    duolingo_usage               = replace_empty(duolingo_usage),
    employment_status            = replace_empty(employment_status),
    gender                       = replace_empty(gender),
    primary_language_commitment  = replace_empty(primary_language_commitment),
    primary_language_review      = replace_empty(primary_language_review),
    primary_language_proficiency = replace_empty(primary_language_proficiency),
    primary_language_motivation  = replace_empty(primary_language_motivation),
    student                      = replace_empty(student)
  )
# this is mainly for visualizations lol

usage <- usage_raw %>% mutate(
  user_id = as.character(user_id),
  duolingo_start_date     = as.character(duolingo_start_date) %>% parse_datetime(format="%D %H:%M"), # locale?
  took_placement_test     = (took_placement_test == "True"), # assume they didn't take placement test if missing
  purchased_subscription  = (purchased_subscription == "True"), # no missing values
  highest_course_progress = set_lower_limit(highest_course_progress, at=1), # cannot have neg progress
  longest_streak          = ignore_max_value(longest_streak), # 6000 days was 16 years ago, Duolingo foudned in 2011
  highest_crown_count     = replace_na(highest_crown_count, with=0)
) %>% 
  # majority of this column is missing, not very useful anymore
  select(-daily_goal) %>% 
  # deduplicate by prefering those who have completed the most lessons
  group_by(user_id) %>% filter(n_lessons_completed == max(n_lessons_completed)) %>% ungroup()

## Normality of time_spent_seconds
qqnorm(survey_raw$time_spent_seconds)
qqnorm(survey$time_spent_seconds)

## DUPLICATED USER_ID ANALYSIS
# seems like users share the same account sometimes? Extremely different surveys
repeat_users <- plyr::count(survey_raw$user_id) %>% filter(freq != 1) %>% select(x) %>% unlist %>% as.character
repeat_surveys <- survey_raw %>% filter(user_id %in% repeat_users) %>% arrange(user_id)
peek <- repeat_surveys %>% 
  select(user_id, age, annual_income, country, duolingo_subscriber, employment_status, primary_language_proficiency, student)
peek

# I don't even understand how there are user statistics with different start dates...
repeat_users <- plyr::count(usage_raw$user_id) %>% filter(freq != 1) %>% select(x) %>% unlist %>% as.character
repeat_surveys <- usage_raw %>% filter(user_id %in% repeat_users) %>% arrange(user_id)
peek <- repeat_surveys %>% 
  select(user_id, duolingo_start_date, purchased_subscription, n_days_on_platform, n_lessons_completed)
peek

## JOINING DATA AND LOOKING AT NUMERIC CORRELATIONS
# filtering for only completed surveys brings users from 96.3% of original to 95.1% of original
df <- inner_join(survey, usage, by="user_id") %>% filter(survey_complete)
numeric_cols <- unlist(lapply(df, is.numeric)) # filter out numeric columns for correlation analysis
nums <- df[ ,numeric_cols]
correlations <- cor(nums)
# take a peak at correlations
corrplot(correlations, type = "upper", order = "hclust", 
         tl.col = "black", tl.srt = 45)
chart.Correlation(nums, histogram=TRUE, pch=19)

# longest_streak has relatively high correlation with everything regarding activity
# variables associated with activty have high correlation with crown count

## VISUALIZATIONS
blank <- theme_bw() + theme(
  panel.border     = element_blank(),
  panel.grid.major = element_blank(),
  panel.grid.minor = element_blank(),
  axis.line        = element_line(colour = "black"))  # removes most formatting 
center_title <- theme(plot.title = element_text(hjust = 0.5))
no_legend <- theme(legend.position="none")

# AGE PIE CHART (how basic and hard to read smh)
df %>% filter(age != "No Response") %>% .$age %>% plyr::count() %>%
  dplyr::rename(Age = x) %>%
  ggplot(mapping = aes("", freq, fill = Age)) +
  geom_bar(width=1, stat="identity") +
  coord_polar("y", start=0) + 
  theme_minimal() + 
  scale_fill_viridis_d() + 
  theme(
    panel.grid = element_blank(),
    axis.title = element_blank(),
    axis.text  = element_blank()
  ) + 
  ggtitle("Distribution of Duolingo User Ages") + center_title

# Age vs Subscription (scaled)
p1 <- df %>% filter(age != "No Response") %>% dplyr::rename(`Duolingo Subscription` = duolingo_subscriber) %>%
  filter(`Duolingo Subscription` != "No Response") %>%
  ggplot(mapping = aes(x = age, fill = `Duolingo Subscription`)) + 
  geom_bar(position = "fill") + blank + center_title +
  theme(
    axis.line.y = element_blank(), 
    axis.text.y = element_blank(),
    axis.ticks.y = element_blank()
  ) + 
  labs(x="Age", y="Proportion") + 
  ggtitle("Duolingo Subscription Across Age Groups") +
  scale_fill_viridis_d(begin=0, end=0.9)

# Age histogram with Subscription facet wrap
p2 <- df %>% filter(age != "No Response") %>% 
  filter(duolingo_subscriber %in% c("No, I have never paid for Duolingo Plus", "Yes, I currently pay for Duolingo Plus")) %>%
  ggplot(mapping = aes(x = age, fill=age)) + 
  geom_histogram(stat="count") + 
  scale_fill_viridis_d() + blank + no_legend + 
  facet_wrap(~duolingo_subscriber) +
  labs(x="Age", y="Count") + 
  ggtitle("Age Distribution of Duolingo Subscribers") + center_title

# AGE VS STUDENT
p3 <- df %>% 
  filter(duolingo_subscriber == "No, I have never paid for Duolingo Plus") %>%
  filter(age %in% c("18-34", "35 - 54")) %>% 
  filter(student != "No Response") %>% dplyr::rename(Student = student) %>%
  ggplot(mapping = aes(x = age, fill = Student)) + 
  geom_bar(position = "fill") + blank +
  scale_fill_viridis_d(begin=0, end=0.75) +
  facet_wrap(~duolingo_subscriber) + 
  labs(x = "Age", y="Proportion") + 
  theme(
    axis.line.y = element_blank(),
    axis.text.y = element_blank(),
    axis.ticks.y = element_blank()
  ) +
  ggtitle("Education Status of (younger) Non-Subscribers") + center_title

p4 <- df %>%
  filter(duolingo_subscriber == "No, I have never paid for Duolingo Plus") %>%
  filter(age %in% c("18-34", "35 - 54")) %>% 
  filter(student == "Not currently a student") %>% {. ->> tmp} %>% .$country %>%
  plyr::count() %>% dplyr::rename(Country = x) %>% 
  bind_cols(duolingo_subscriber=rep("No, I have never paid for Duolingo Plus", 10)) %>%
  ggplot(mapping = aes(x = reorder(Country, -freq), freq, fill = Country)) + 
  geom_bar(stat="identity") + 
  scale_fill_viridis_d(begin=0, end=0.8) + blank + no_legend + 
  facet_wrap(~duolingo_subscriber) + 
  labs(x = "Country", y = "Count") + 
  ggtitle("Nationality of Non-Student Non-Subscribers (ages 18-54)") + center_title

multiplot(p1, p3, p2, p4, cols=2)

# WRITE OUT DATA
write_csv(df, "combined_data.csv")