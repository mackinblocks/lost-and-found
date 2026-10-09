from flask import Flask, render_template, request, redirect, url_for
from datetime import datetime

app = Flask(__name__)

# In-memory store (replace with a DB like SQLite/PostgreSQL for production)
posts = [
    {
        "id": 1,
        "type": "lost",
        "title": "Lost: Black Northface Backpack",
        "description": "Left it near the UC Library main entrance. Has a red keychain and initials 'J.R.' on the front pocket.",
        "location": "Langsam Library",
        "contact": "jramos@mail.uc.edu",
        "date": "2026-10-07",
        "timestamp": datetime(2026, 10, 7, 14, 30),
    },
    {
        "id": 2,
        "type": "found",
        "title": "Found: AirPods Pro Case",
        "description": "Found a white AirPods Pro case near the Student Union food court. No AirPods inside.",
        "location": "Tangeman University Center",
        "contact": "smith.a@mail.uc.edu",
        "date": "2026-10-08",
        "timestamp": datetime(2026, 10, 8, 9, 15),
    },
]
next_id = 3


@app.route("/")
def index():
    filter_type = request.args.get("type", "all")
    query = request.args.get("q", "").lower()

    filtered = posts
    if filter_type in ("lost", "found"):
        filtered = [p for p in filtered if p["type"] == filter_type]
    if query:
        filtered = [
            p for p in filtered
            if query in p["title"].lower() or query in p["description"].lower() or query in p["location"].lower()
        ]

    filtered = sorted(filtered, key=lambda p: p["timestamp"], reverse=True)
    return render_template("index.html", posts=filtered, filter_type=filter_type, query=query)


@app.route("/post/new", methods=["GET", "POST"])
def new_post():
    if request.method == "POST":
        global next_id
        post = {
            "id": next_id,
            "type": request.form["type"],
            "title": request.form["title"],
            "description": request.form["description"],
            "location": request.form["location"],
            "contact": request.form["contact"],
            "date": request.form["date"],
            "timestamp": datetime.now(),
        }
        posts.append(post)
        next_id += 1
        return redirect(url_for("index"))
    return render_template("new_post.html")


@app.route("/post/<int:post_id>")
def view_post(post_id):
    post = next((p for p in posts if p["id"] == post_id), None)
    if post is None:
        return "Post not found", 404
    return render_template("post.html", post=post)


@app.route("/post/<int:post_id>/delete", methods=["POST"])
def delete_post(post_id):
    global posts
    posts = [p for p in posts if p["id"] != post_id]
    return redirect(url_for("index"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", debug=True)
