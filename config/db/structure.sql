CREATE TABLE `schema_migrations`(`filename` varchar(255) NOT NULL PRIMARY KEY);
CREATE TABLE `schema_info`(`version` integer DEFAULT(0) NOT NULL);
CREATE TABLE `scopes`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `name` varchar(255) NOT NULL,
  `parent_id` integer NULL REFERENCES `scopes`,
  `created_at` timestamp NOT NULL,
  `updated_at` timestamp NOT NULL
);
CREATE INDEX `scopes_name_index` ON `scopes`(`name`);
CREATE INDEX `scopes_parent_id_index` ON `scopes`(`parent_id`);
CREATE TABLE `owners`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `name` varchar(255) NOT NULL,
  `public_key` varchar(255) NULL,
  `api_key` varchar(255) NULL,
  `created_at` timestamp NOT NULL,
  `updated_at` timestamp NOT NULL,
  `account_id` integer NULL
);
CREATE UNIQUE INDEX `owners_name_index` ON `owners`(`name`);
CREATE UNIQUE INDEX `owners_api_key_index` ON `owners`(`api_key`);
CREATE TABLE `gems`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `name` varchar(255) NOT NULL,
  `version` varchar(255) NOT NULL,
  `scope_id` integer NULL REFERENCES `scopes`,
  `file_path` varchar(255) NOT NULL,
  `yanked` boolean DEFAULT(0),
  `created_at` timestamp NOT NULL,
  `updated_at` timestamp NOT NULL
);
CREATE INDEX `gems_name_scope_id_index` ON `gems`(`name`, `scope_id`);
CREATE INDEX `gems_version_index` ON `gems`(`version`);
CREATE INDEX `gems_yanked_index` ON `gems`(`yanked`);
CREATE TABLE `gem_owners`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `gem_id` integer NOT NULL REFERENCES `gems`,
  `owner_id` integer NOT NULL REFERENCES `owners`,
  `created_at` timestamp NOT NULL
);
CREATE UNIQUE INDEX `gem_owners_gem_id_owner_id_index` ON `gem_owners`(
  `gem_id`,
  `owner_id`
);
CREATE TABLE `scope_owners`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `scope_id` integer NOT NULL REFERENCES `scopes`,
  `owner_id` integer NOT NULL REFERENCES `owners`,
  `created_at` timestamp NOT NULL
);
CREATE UNIQUE INDEX `scope_owners_scope_id_owner_id_index` ON `scope_owners`(
  `scope_id`,
  `owner_id`
);
CREATE TABLE `known_servers`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `base_url` varchar(255) NOT NULL,
  `public_key_b64` varchar(255) NOT NULL,
  `subscribed` boolean DEFAULT(0),
  `last_announced_at` timestamp NULL,
  `last_seen_at` timestamp NULL,
  `created_at` timestamp NOT NULL,
  `updated_at` timestamp NOT NULL
);
CREATE UNIQUE INDEX `known_servers_base_url_index` ON `known_servers`(
  `base_url`
);
CREATE INDEX `known_servers_public_key_b64_index` ON `known_servers`(
  `public_key_b64`
);
CREATE INDEX `known_servers_subscribed_index` ON `known_servers`(`subscribed`);
CREATE TABLE `federated_gems`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `name` varchar(255) NOT NULL,
  `version` varchar(255) NOT NULL,
  `scope_id` integer NULL REFERENCES `scopes`,
  `origin_server_id` integer NOT NULL REFERENCES `known_servers`,
  `digest_sha256` varchar(255) NOT NULL,
  `signature_b64` varchar(255) NOT NULL,
  `created_at` timestamp NOT NULL
);
CREATE UNIQUE INDEX `idx_fed_gems_uniqueness` ON `federated_gems`(
  `name`,
  `version`,
  `scope_id`,
  `origin_server_id`
);
CREATE TABLE `account_statuses`(
  `id` integer NOT NULL PRIMARY KEY,
  `name` varchar(255) NOT NULL UNIQUE
);
CREATE TABLE `accounts`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `status_id` integer DEFAULT(1) NOT NULL REFERENCES `account_statuses`,
  `email` varchar(255) NOT NULL,
  `password_hash` varchar(255) NOT NULL
);
CREATE UNIQUE INDEX `accounts_email_index` ON `accounts`(`email`);
CREATE TABLE `account_password_reset_keys`(
  `id` bigint NOT NULL PRIMARY KEY REFERENCES `accounts`,
  `key` varchar(255) NOT NULL,
  `deadline` timestamp NOT NULL,
  `email_last_sent` timestamp DEFAULT(datetime(CURRENT_TIMESTAMP, 'localtime')) NOT NULL
);
CREATE TABLE `account_verification_keys`(
  `id` bigint NOT NULL PRIMARY KEY REFERENCES `accounts`,
  `key` varchar(255) NOT NULL,
  `requested_at` timestamp DEFAULT(datetime(CURRENT_TIMESTAMP, 'localtime')) NOT NULL,
  `email_last_sent` timestamp DEFAULT(datetime(CURRENT_TIMESTAMP, 'localtime')) NOT NULL
);
CREATE TABLE `account_login_change_keys`(
  `id` bigint NOT NULL PRIMARY KEY REFERENCES `accounts`,
  `key` varchar(255) NOT NULL,
  `login` varchar(255) NOT NULL,
  `deadline` timestamp NOT NULL
);
CREATE TABLE `account_remember_keys`(
  `id` bigint NOT NULL PRIMARY KEY REFERENCES `accounts`,
  `key` varchar(255) NOT NULL,
  `deadline` timestamp NOT NULL
);
CREATE UNIQUE INDEX `owners_account_id_index` ON `owners`(`account_id`);
INSERT INTO schema_migrations (filename) VALUES
;
