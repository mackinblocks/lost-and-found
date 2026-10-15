# UC Lost & Found

A Flask-based message board for posting and finding lost items. Built with Python, Flask.


install wsl by running
````
wsl --install
````
when done reboot computer then run docker install file default everything is fine.


## Quick Start

### Option 1 — Docker (Recommended, no Python needed)



**Requirements:** [Docker Desktop](https://www.docker.com/products/docker-desktop/)

```bash
git clone https://github.com/mackinblocks/lost-and-found.git
cd lost-and-found
docker compose up --build
```

Open **http://localhost:5000** in your browser.

To stop:
```bash
docker compose down
```

---

### Option 2 — Run with Python (Manual)

**Requirements:** Python 3.10+

```bash
git clone https://github.com/mackinblocks/lost-and-found.git
cd lost-and-found

# Mac/Linux
python3 -m venv venv
source venv/bin/activate

# Windows
python3 -m venv venv
venv\Scripts\activate

pip install flask
python app.py
```

Open **http://localhost:5000** in your browser.

---

## Project Structure

```
lost-and-found/
├── app.py                  # Flask application
├── Dockerfile              # Docker image config
├── docker-compose.yml      # Docker Compose config
├── requirements.txt        # Python dependencies
├── static/
│   └── style.css           # Stylesheet
└── templates/
    ├── base.html           # Base layout
    ├── index.html          # Main board page
    ├── new_post.html       # New post form
    └── post.html           # Post detail page
```

---

## Possible Features

-  Message board with Lost & Found posts
-  Search by title, description, or location
-  Filter by Lost / Found
-  Create and delete posts
-  Responsive, mobile-friendly layout
-  login screen

---

## Tech Stack

- **Backend:** Python, Flask
- **Frontend:** HTML, CSS (vanilla)

---

## Contributing

1. Fork the repo
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit your changes: `git commit -m "add your feature"`
4. Push to the branch: `git push origin feature/your-feature`
5. Open a Pull Request
