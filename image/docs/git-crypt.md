## Encrypting Git Repositories

If you need to encrypt files within a git repository it can be done using [git-crypt](https://github.com/AGWA/git-crypt). GPG encrypted repos may be unencrypted using one of the following methods.

1. Upload the GPG public key of the user to use for decryption as `<ROOT USER HOME>/git-crypt-user.pem`.

  Export your GPG as follows and base64 encode it. 

  ```
  gpg --export-secret-key -a msamaratunga@appbricks.net | base64
  ```

  Copy the output as the content for the cloud-config configuration file saved to `<ROOT USER HOME>/git-crypt-user.pem` as follows.

  ```
  #cloud-config

  write_files:
    content: !!binary |
      <BASE64 encoded key file>
    path: /root/git-crypt-user.pem
    permissions: '0600'
  ```

  This will add the gpg key of the git-crypt user to the target instance's gpg database, so that any encrypted files within a repository can be unlocked using git-crypt.

2. Upload a symmetric key for decryption as `<ROOT USER HOME>/git-crypt-key.pem`. As above the exported key needs to be base64 encoded and passed as file content in the cloud-config configuration file.
