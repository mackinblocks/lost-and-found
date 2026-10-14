#!/bin/bash
set -e

PROJECT="/mnt/c/Users/DTobe/Desktop/lost-and-found"
cd "$PROJECT"

mkdir -p templates static/uploads

# ── app.py ──────────────────────────────────────────────────────────────────
cat > app.py << 'PYEOF'
import os
from flask import Flask, render_template, request, redirect, url_for, flash, session
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename
from datetime import datetime
from functools import wraps

app = Flask(__name__)
app.secret_key = "uc-lost-and-found-secret"

app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///lostfound.db"
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

UPLOAD_FOLDER = os.path.join("static", "uploads")
ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "gif", "webp"}
app.config["UPLOAD_FOLDER"] = UPLOAD_FOLDER
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

db = SQLAlchemy(app)


class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    posts = db.relationship("Post", backref="author", lazy=True)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)


class Post(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    type = db.Column(db.String(10), nullable=False, default="lost")
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text, nullable=False)
    location = db.Column(db.String(200), nullable=False)
    contact = db.Column(db.String(200), nullable=False)
    date = db.Column(db.String(20), nullable=False)
    image_filename = db.Column(db.String(300), nullable=True)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    resolved = db.Column(db.Boolean, default=False)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)


def allowed_file(filename):
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if "user_id" not in session:
            flash("Please log in to continue.", "warning")
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return decorated


def current_user():
    if "user_id" in session:
        return User.query.get(session["user_id"])
    return None


app.jinja_env.globals["current_user"] = current_user


@app.route("/")
def index():
    filter_type = request.args.get("type", "all")
    query = request.args.get("q", "").lower()

    posts = Post.query
    if filter_type == "lost":
        posts = posts.filter_by(type="lost")
    if query:
        posts = posts.filter(
            db.or_(
                Post.title.ilike(f"%{query}%"),
                Post.description.ilike(f"%{query}%"),
                Post.location.ilike(f"%{query}%"),
            )
        )
    posts = posts.order_by(Post.timestamp.desc()).all()
    return render_template("index.html", posts=posts, filter_type=filter_type, query=query)


@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        username = request.form["username"].strip()
        email = request.form["email"].strip()
        password = request.form["password"]

        if User.query.filter_by(username=username).first():
            flash("Username already taken.", "danger")
            return redirect(url_for("register"))
        if User.query.filter_by(email=email).first():
            flash("Email already registered.", "danger")
            return redirect(url_for("register"))

        user = User(username=username, email=email)
        user.set_password(password)
        db.session.add(user)
        db.session.commit()
        session["user_id"] = user.id
        flash("Account created! Welcome to Bearcats Lost & Found.", "success")
        return redirect(url_for("index"))
    return render_template("register.html")


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form["username"].strip()
        password = request.form["password"]
        user = User.query.filter_by(username=username).first()
        if user and user.check_password(password):
            session["user_id"] = user.id
            flash(f"Welcome back, {user.username}!", "success")
            return redirect(url_for("index"))
        flash("Invalid username or password.", "danger")
    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    flash("You have been logged out.", "info")
    return redirect(url_for("index"))


@app.route("/post/new", methods=["GET", "POST"])
@login_required
def new_post():
    if request.method == "POST":
        image_filename = None
        file = request.files.get("image")
        if file and file.filename and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            unique_name = f"{datetime.utcnow().strftime('%Y%m%d%H%M%S')}_{filename}"
            file.save(os.path.join(app.config["UPLOAD_FOLDER"], unique_name))
            image_filename = unique_name

        post = Post(
            type="lost",
            title=request.form["title"],
            description=request.form["description"],
            location=request.form["location"],
            contact=request.form["contact"],
            date=request.form["date"],
            image_filename=image_filename,
            user_id=session["user_id"],
        )
        db.session.add(post)
        db.session.commit()
        flash("Post submitted!", "success")
        return redirect(url_for("index"))
    return render_template("new_post.html")


@app.route("/post/<int:post_id>")
def view_post(post_id):
    post = Post.query.get_or_404(post_id)
    return render_template("post.html", post=post)


@app.route("/post/<int:post_id>/delete", methods=["POST"])
@login_required
def delete_post(post_id):
    post = Post.query.get_or_404(post_id)
    if post.user_id != session["user_id"]:
        flash("You can only delete your own posts.", "danger")
        return redirect(url_for("view_post", post_id=post_id))
    if post.image_filename:
        try:
            os.remove(os.path.join(app.config["UPLOAD_FOLDER"], post.image_filename))
        except FileNotFoundError:
            pass
    db.session.delete(post)
    db.session.commit()
    flash("Post deleted.", "info")
    return redirect(url_for("index"))


@app.route("/post/<int:post_id>/resolve", methods=["POST"])
@login_required
def resolve_post(post_id):
    post = Post.query.get_or_404(post_id)
    if post.user_id != session["user_id"]:
        flash("You can only mark your own posts as found.", "danger")
        return redirect(url_for("view_post", post_id=post_id))
    post.resolved = not post.resolved
    db.session.commit()
    return redirect(url_for("view_post", post_id=post_id))


if __name__ == "__main__":
    with app.app_context():
        db.create_all()
    app.run(host="0.0.0.0", debug=True)
PYEOF

# ── requirements.txt ─────────────────────────────────────────────────────────
cat > requirements.txt << 'EOF'
flask
flask-sqlalchemy
werkzeug
EOF

# ── Dockerfile ───────────────────────────────────────────────────────────────
cat > Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 5000
CMD ["python", "app.py"]
EOF

# ── docker-compose.yml ───────────────────────────────────────────────────────
cat > docker-compose.yml << 'EOF'
services:
  web:
    build: .
    ports:
      - "5000:5000"
    volumes:
      - db_data:/app/instance
      - uploads:/app/static/uploads

volumes:
  db_data:
  uploads:
EOF

# ── .dockerignore ─────────────────────────────────────────────────────────────
cat > .dockerignore << 'EOF'
venv
__pycache__
*.pyc
.git
static/uploads/
EOF

# ── templates/base.html ──────────────────────────────────────────────────────
cat > templates/base.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>{% block title %}UC Lost & Found{% endblock %}</title>
  <link rel="stylesheet" href="{{ url_for('static', filename='style.css') }}"/>
</head>
<body>
  <header>
    <div class="header-inner">
      <div class="logo">
        <span class="logo-icon">🐾</span>
        <div>
          <h1>Bearcats Lost & Found</h1>
          <p>University of Cincinnati Community Board</p>
        </div>
      </div>
      <nav class="header-nav">
        {% if current_user() %}
          <span class="nav-user">👤 {{ current_user().username }}</span>
          <a href="{{ url_for('new_post') }}" class="btn btn-primary">+ New Post</a>
          <a href="{{ url_for('logout') }}" class="btn btn-ghost">Log Out</a>
        {% else %}
          <a href="{{ url_for('login') }}" class="btn btn-ghost">Log In</a>
          <a href="{{ url_for('register') }}" class="btn btn-primary">Register</a>
        {% endif %}
      </nav>
    </div>
  </header>

  <main>
    {% with messages = get_flashed_messages(with_categories=true) %}
      {% if messages %}
        <div class="flash-messages">
          {% for category, message in messages %}
            <div class="flash flash-{{ category }}">{{ message }}</div>
          {% endfor %}
        </div>
      {% endif %}
    {% endwith %}
    {% block content %}{% endblock %}
  </main>

  <footer>
    <p>University of Cincinnati &mdash; Lost &amp; Found Message Board &mdash; For campus use only</p>
  </footer>
</body>
</html>
EOF

# ── templates/index.html ─────────────────────────────────────────────────────
cat > templates/index.html << 'EOF'
{% extends "base.html" %}
{% block content %}

<section class="board-controls">
  <form method="GET" action="/" class="search-bar">
    <input type="text" name="q" placeholder="Search by title, description, or location…" value="{{ query }}"/>
    <button type="submit" class="btn btn-secondary">Search</button>
    {% if query %}<a href="/" class="btn btn-ghost" style="color:#222;">Clear</a>{% endif %}
  </form>

  <div class="filter-tabs">
    <a href="/?type=all{% if query %}&q={{ query }}{% endif %}"
       class="tab {% if filter_type == 'all' %}active{% endif %}">All</a>
    <a href="/?type=lost{% if query %}&q={{ query }}{% endif %}"
       class="tab lost {% if filter_type == 'lost' %}active{% endif %}">Lost</a>
  </div>
</section>

<section class="board">
  {% if posts %}
    <div class="post-grid">
      {% for post in posts %}
      <a href="{{ url_for('view_post', post_id=post.id) }}" class="post-card {{ 'found' if post.resolved else 'lost' }}">
        {% if post.image_filename %}
          <img class="post-card-thumb" src="{{ url_for('static', filename='uploads/' + post.image_filename) }}" alt="Item photo" />
        {% endif %}
        <div style="display:flex; gap:0.4rem; flex-wrap:wrap;">
          {% if post.resolved %}
            <span class="badge found">FOUND</span>
          {% else %}
            <span class="badge lost">LOST</span>
          {% endif %}
        </div>
        <h2>{{ post.title }}</h2>
        <p class="description">{{ post.description[:120] }}{% if post.description|length > 120 %}…{% endif %}</p>
        <div class="meta">
          <span>📍 {{ post.location }}</span>
          <span>📅 {{ post.date }}</span>
          <span>👤 {{ post.author.username }}</span>
        </div>
      </a>
      {% endfor %}
    </div>
  {% else %}
    <div class="empty-state">
      <p>No posts found. <a href="{{ url_for('new_post') }}">Be the first to post!</a></p>
    </div>
  {% endif %}
</section>

{% endblock %}
EOF

# ── templates/new_post.html ──────────────────────────────────────────────────
cat > templates/new_post.html << 'EOF'
{% extends "base.html" %}
{% block title %}New Post – UC Lost & Found{% endblock %}
{% block content %}
<div class="form-container">
  <h2>Report a Lost Item</h2>
  <form method="POST" action="{{ url_for('new_post') }}" enctype="multipart/form-data">

    <input type="hidden" name="type" value="lost" />

    <div class="form-group">
      <label for="title">Title</label>
      <input type="text" id="title" name="title" placeholder="e.g. Lost: Blue Water Bottle" required />
    </div>

    <div class="form-group">
      <label for="description">Description</label>
      <textarea id="description" name="description" rows="4"
        placeholder="Describe the item — color, brand, distinguishing features…" required></textarea>
    </div>

    <div class="form-group">
      <label for="location">Location</label>
      <input type="text" id="location" name="location" placeholder="e.g. Baldwin Hall Room 201" required />
    </div>

    <div class="form-group">
      <label for="contact">Contact (email or phone)</label>
      <input type="text" id="contact" name="contact" placeholder="e.g. yourname@mail.uc.edu" required />
    </div>

    <div class="form-group">
      <label for="date">Date Lost</label>
      <input type="date" id="date" name="date" required />
    </div>

    <div class="form-group">
      <label for="image">Photo (optional)</label>
      <input type="file" id="image" name="image" accept="image/*" />
    </div>

    <div class="form-actions">
      <a href="{{ url_for('index') }}" class="btn btn-ghost" style="color:#222;">Cancel</a>
      <button type="submit" class="btn btn-primary">Submit Post</button>
    </div>
  </form>
</div>
{% endblock %}
EOF

# ── templates/post.html ──────────────────────────────────────────────────────
cat > templates/post.html << 'EOF'
{% extends "base.html" %}
{% block title %}{{ post.title }} – UC Lost & Found{% endblock %}
{% block content %}
<div class="post-detail">
  <a href="{{ url_for('index') }}" class="back-link">← Back to Board</a>

  <div class="detail-card {{ 'found' if post.resolved else 'lost' }}">
    <div class="badge-row">
      {% if post.resolved %}
        <span class="badge found">FOUND</span>
      {% else %}
        <span class="badge lost">LOST</span>
      {% endif %}
    </div>

    <h2>{{ post.title }}</h2>

    {% if post.image_filename %}
    <div class="post-image">
      <img src="{{ url_for('static', filename='uploads/' + post.image_filename) }}" alt="Item photo" />
    </div>
    {% endif %}

    <div class="detail-body">
      <p>{{ post.description }}</p>
    </div>

    <div class="detail-meta">
      <div class="meta-item">
        <span class="meta-label">📍 Location</span>
        <span>{{ post.location }}</span>
      </div>
      <div class="meta-item">
        <span class="meta-label">📅 Date</span>
        <span>{{ post.date }}</span>
      </div>
      <div class="meta-item">
        <span class="meta-label">✉️ Contact</span>
        <span>{{ post.contact }}</span>
      </div>
      <div class="meta-item">
        <span class="meta-label">👤 Posted by</span>
        <span>{{ post.author.username }}</span>
      </div>
    </div>

    {% if current_user() and current_user().id == post.user_id %}
    <div class="post-actions">
      <form method="POST" action="{{ url_for('resolve_post', post_id=post.id) }}" style="display:inline;">
        <button type="submit" class="btn btn-secondary">
          {% if post.resolved %}Unmark as Found{% else %}Mark as Found{% endif %}
        </button>
      </form>
      <form method="POST" action="{{ url_for('delete_post', post_id=post.id) }}"
            onsubmit="return confirm('Delete this post?');" style="display:inline;">
        <button type="submit" class="btn btn-danger">Delete Post</button>
      </form>
    </div>
    {% endif %}
  </div>
</div>
{% endblock %}
EOF

# ── templates/register.html ──────────────────────────────────────────────────
cat > templates/register.html << 'EOF'
{% extends "base.html" %}
{% block title %}Register – UC Lost & Found{% endblock %}
{% block content %}
<div class="form-container">
  <h2>Create an Account</h2>
  <form method="POST" action="{{ url_for('register') }}">

    <div class="form-group">
      <label for="username">Username</label>
      <input type="text" id="username" name="username" placeholder="e.g. bearcatjoe" required />
    </div>

    <div class="form-group">
      <label for="email">Email</label>
      <input type="email" id="email" name="email" placeholder="yourname@mail.uc.edu" required />
    </div>

    <div class="form-group">
      <label for="password">Password</label>
      <input type="password" id="password" name="password" placeholder="Choose a strong password" required />
    </div>

    <div class="form-actions">
      <button type="submit" class="btn btn-primary">Create Account</button>
    </div>

    <p class="form-footer">Already have an account? <a href="{{ url_for('login') }}">Log in</a></p>
  </form>
</div>
{% endblock %}
EOF

# ── templates/login.html ─────────────────────────────────────────────────────
cat > templates/login.html << 'EOF'
{% extends "base.html" %}
{% block title %}Log In – UC Lost & Found{% endblock %}
{% block content %}
<div class="form-container">
  <h2>Log In</h2>
  <form method="POST" action="{{ url_for('login') }}">

    <div class="form-group">
      <label for="username">Username</label>
      <input type="text" id="username" name="username" placeholder="Your username" required />
    </div>

    <div class="form-group">
      <label for="password">Password</label>
      <input type="password" id="password" name="password" placeholder="Your password" required />
    </div>

    <div class="form-actions">
      <button type="submit" class="btn btn-primary">Log In</button>
    </div>

    <p class="form-footer">Don't have an account? <a href="{{ url_for('register') }}">Register</a></p>
  </form>
</div>
{% endblock %}
EOF

# ── static/style.css ─────────────────────────────────────────────────────────
cat > static/style.css << 'EOF'
/* ── Reset & Variables ── */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  --uc-red:     #e00122;
  --uc-black:   #1a1a1a;
  --lost-color: #e00122;
  --found-color:#1a7f4b;
  --bg:         #f4f4f4;
  --card-bg:    #ffffff;
  --border:     #ddd;
  --text:       #222;
  --muted:      #666;
  --radius:     10px;
  --shadow:     0 2px 8px rgba(0,0,0,0.08);
}

body {
  font-family: 'Segoe UI', system-ui, sans-serif;
  background: var(--bg);
  color: var(--text);
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

/* ── Header ── */
header {
  background: var(--uc-black);
  color: white;
  padding: 1rem 2rem;
  border-bottom: 4px solid var(--uc-red);
}
.header-inner {
  max-width: 1100px;
  margin: 0 auto;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
}
.logo { display: flex; align-items: center; gap: 0.75rem; }
.logo-icon { font-size: 2rem; }
.logo h1 { font-size: 1.4rem; font-weight: 700; color: white; }
.logo p  { font-size: 0.8rem; color: #aaa; }
.header-nav { display: flex; align-items: center; gap: 0.75rem; }
.nav-user { color: #ccc; font-size: 0.9rem; }

/* ── Footer ── */
footer {
  background: var(--uc-black);
  color: #888;
  text-align: center;
  padding: 1rem;
  font-size: 0.8rem;
  margin-top: auto;
  border-top: 3px solid var(--uc-red);
}

/* ── Main ── */
main {
  max-width: 1100px;
  margin: 2rem auto;
  padding: 0 1.5rem;
  width: 100%;
  flex: 1;
}

/* ── Buttons ── */
.btn {
  display: inline-block;
  padding: 0.55rem 1.2rem;
  border-radius: 6px;
  font-size: 0.9rem;
  font-weight: 600;
  cursor: pointer;
  text-decoration: none;
  border: none;
  transition: opacity 0.15s, transform 0.1s;
}
.btn:hover { opacity: 0.88; transform: translateY(-1px); }
.btn-primary   { background: var(--uc-red);   color: white; }
.btn-secondary { background: var(--uc-black); color: white; }
.btn-ghost     { background: transparent; color: white; border: 1.5px solid rgba(255,255,255,0.5); }
.btn-ghost:hover { border-color: white; }
.btn-danger    { background: #c0392b; color: white; }

/* ── Board Controls ── */
.board-controls {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  margin-bottom: 1.5rem;
}
.search-bar {
  display: flex;
  gap: 0.5rem;
  flex: 1;
  min-width: 260px;
}
.search-bar input {
  flex: 1;
  padding: 0.55rem 0.9rem;
  border: 1.5px solid var(--border);
  border-radius: 6px;
  font-size: 0.9rem;
}
.filter-tabs { display: flex; gap: 0.5rem; }
.tab {
  padding: 0.45rem 1rem;
  border-radius: 20px;
  font-size: 0.85rem;
  font-weight: 600;
  text-decoration: none;
  background: white;
  border: 1.5px solid var(--border);
  color: var(--muted);
  transition: all 0.15s;
}
.tab.active, .tab:hover { color: white; border-color: transparent; }
.tab.active             { background: var(--uc-black); }
.tab.lost.active        { background: var(--lost-color); }
.tab.found.active       { background: var(--found-color); }

/* ── Post Grid ── */
.post-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 1.25rem;
}
.post-card {
  background: var(--card-bg);
  border-radius: var(--radius);
  padding: 1.25rem;
  box-shadow: var(--shadow);
  text-decoration: none;
  color: var(--text);
  border-top: 4px solid var(--border);
  transition: transform 0.15s, box-shadow 0.15s;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}
.post-card:hover { transform: translateY(-3px); box-shadow: 0 6px 18px rgba(0,0,0,0.12); }
.post-card.lost  { border-top-color: var(--lost-color); }
.post-card.found { border-top-color: var(--found-color); }
.post-card h2    { font-size: 1rem; font-weight: 700; }
.description     { font-size: 0.88rem; color: var(--muted); line-height: 1.5; }
.meta            { display: flex; flex-wrap: wrap; gap: 0.5rem; font-size: 0.8rem; color: var(--muted); margin-top: auto; }

/* ── Badge ── */
.badge {
  display: inline-block;
  padding: 0.2rem 0.65rem;
  border-radius: 20px;
  font-size: 0.72rem;
  font-weight: 700;
  letter-spacing: 0.05em;
  width: fit-content;
}
.badge.lost  { background: #fde8eb; color: var(--lost-color); }
.badge.found { background: #e0f5ea; color: var(--found-color); }

/* ── Empty State ── */
.empty-state {
  text-align: center;
  padding: 4rem 1rem;
  color: var(--muted);
  font-size: 1rem;
}
.empty-state a { color: var(--uc-red); font-weight: 600; }

/* ── Form ── */
.form-container {
  max-width: 620px;
  margin: 0 auto;
  background: var(--card-bg);
  border-radius: var(--radius);
  padding: 2rem;
  box-shadow: var(--shadow);
}
.form-container h2 { margin-bottom: 1.5rem; font-size: 1.3rem; }
.form-group { display: flex; flex-direction: column; gap: 0.4rem; margin-bottom: 1.1rem; }
.form-group label { font-weight: 600; font-size: 0.9rem; }
.form-group input,
.form-group textarea,
.form-group select {
  padding: 0.6rem 0.85rem;
  border: 1.5px solid var(--border);
  border-radius: 6px;
  font-size: 0.9rem;
  font-family: inherit;
  transition: border-color 0.15s;
}
.form-group input:focus,
.form-group textarea:focus { outline: none; border-color: var(--uc-red); }
.form-actions { display: flex; justify-content: flex-end; gap: 0.75rem; margin-top: 1.5rem; }

/* ── Post Detail ── */
.post-detail { max-width: 700px; margin: 0 auto; }
.back-link { display: inline-block; margin-bottom: 1rem; color: var(--uc-red); font-weight: 600; text-decoration: none; }
.back-link:hover { text-decoration: underline; }
.detail-card {
  background: var(--card-bg);
  border-radius: var(--radius);
  padding: 2rem;
  box-shadow: var(--shadow);
  border-top: 5px solid var(--border);
}
.detail-card.lost  { border-top-color: var(--lost-color); }
.detail-card.found { border-top-color: var(--found-color); }
.detail-card h2 { font-size: 1.4rem; margin: 0.75rem 0; }
.detail-body { font-size: 0.95rem; line-height: 1.7; color: var(--text); margin: 1rem 0; }
.detail-meta { display: flex; flex-direction: column; gap: 0.6rem; border-top: 1px solid var(--border); padding-top: 1rem; }
.meta-item { display: flex; gap: 0.75rem; font-size: 0.9rem; }
.meta-label { font-weight: 700; min-width: 110px; }

/* ── Flash Messages ── */
.flash-messages { margin-bottom: 1.25rem; }
.flash {
  padding: 0.75rem 1rem;
  border-radius: 6px;
  margin-bottom: 0.5rem;
  font-size: 0.9rem;
  font-weight: 500;
}
.flash-success { background: #e0f5ea; color: #1a7f4b; }
.flash-danger  { background: #fde8eb; color: #c0392b; }
.flash-warning { background: #fff3cd; color: #856404; }
.flash-info    { background: #e8f4fd; color: #0c5460; }

/* ── Post Image ── */
.post-image { margin: 1rem 0; }
.post-image img {
  max-width: 100%;
  border-radius: var(--radius);
  box-shadow: var(--shadow);
}
.post-card-thumb {
  width: 100%;
  height: 160px;
  object-fit: cover;
  border-radius: 6px;
  margin-bottom: 0.5rem;
}

/* ── Badge Row ── */
.badge-row { display: flex; gap: 0.5rem; flex-wrap: wrap; margin-bottom: 0.5rem; }

/* ── Post Actions ── */
.post-actions { display: flex; gap: 0.75rem; margin-top: 1.5rem; flex-wrap: wrap; }

/* ── Form Footer ── */
.form-footer { text-align: center; margin-top: 1rem; font-size: 0.9rem; color: var(--muted); }
.form-footer a { color: var(--uc-red); font-weight: 600; text-decoration: none; }
.form-footer a:hover { text-decoration: underline; }

/* ── Responsive ── */
@media (max-width: 600px) {
  .header-inner { flex-direction: column; align-items: flex-start; }
  .board-controls { flex-direction: column; }
  .filter-tabs { flex-wrap: wrap; }
}
EOF

echo ""
echo "✅ All files written successfully!"
echo ""
echo "Next steps:"
echo "  docker compose down"
echo "  docker compose up --build"
