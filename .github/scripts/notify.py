"""Надсилає всім користувачам сповіщення «Доступне оновлення» через Firebase.

Запускається з GitHub Actions після створення Release.
Ключ сервісного акаунта береться з секрету FIREBASE_SERVICE_ACCOUNT.
Тема «updates» має збігатися з kUpdatesTopic у lib/app_config.dart.
"""

import json
import os
import subprocess
import sys

import google.auth.transport.requests
import requests
from google.oauth2 import service_account

TOPIC = "updates"


def main() -> int:
    version, build = sys.argv[1], sys.argv[2]

    info = json.loads(os.environ["FIREBASE_SERVICE_ACCOUNT"])
    credentials = service_account.Credentials.from_service_account_info(
        info, scopes=["https://www.googleapis.com/auth/firebase.messaging"]
    )
    credentials.refresh(google.auth.transport.requests.Request())

    # Перший рядок тексту коміту стає текстом сповіщення.
    subject = subprocess.check_output(
        ["git", "log", "-1", "--pretty=%s"], text=True
    ).strip()

    message = {
        "message": {
            "topic": TOPIC,
            "notification": {
                "title": f"Доступне оновлення {version}",
                "body": subject[:200] or "Вийшла нова версія додатка",
            },
            "data": {"type": "update", "build": str(build)},
            "android": {"priority": "HIGH"},
        }
    }

    url = f"https://fcm.googleapis.com/v1/projects/{info['project_id']}/messages:send"
    response = requests.post(
        url,
        headers={"Authorization": f"Bearer {credentials.token}"},
        json=message,
        timeout=30,
    )
    if response.status_code != 200:
        print(f"Не вдалося надіслати сповіщення: {response.status_code}\n{response.text}")
        return 1
    print("Сповіщення надіслано:", response.json().get("name"))
    return 0


if __name__ == "__main__":
    sys.exit(main())